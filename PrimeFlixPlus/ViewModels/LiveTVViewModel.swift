import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class LiveTVViewModel: ObservableObject {
    
    // MARK: - UI State
    @Published var favoriteChannels: [Channel] = []
    @Published var recentChannels: [Channel] = []
    @Published var allGroups: [String] = []
    
    // Lazy loaded content for lanes
    @Published var channelsByGroup: [String: [Channel]] = []
    
    // EPG Data (Map: Channel URL -> Current Program)
    @Published var currentPrograms: [String: Programme] = [:]
    @Published var isLoading: Bool = true
    
    // MARK: - Internal
    private var repository: PrimeFlixRepository?
    private var epgService: EpgService?
    private var cancellables = Set<AnyCancellable>()
    
    // EPG Batching
    private var epgRefreshQueue: Set<Channel> = []
    private var epgTimer: Timer?
    
    // MARK: - Configuration
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.epgService = EpgService(context: repository.container.viewContext)
        
        loadData()
        setupListeners()
        startEpgBatcher()
        
        // Periodic EPG Cleanup (remove old programs every 10 mins)
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.epgService?.pruneExpiredPrograms()
            }
        }
    }
    
    private func setupListeners() {
        // Refresh when favorites or history change
        repository?.objectWillChange
            .debounce(for: .milliseconds(1000), scheduler: RunLoop.main) // Increased debounce to prevent stutter
            .sink { [weak self] _ in self?.refreshLists() }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    
    func loadData() {
        self.isLoading = true
        refreshLists()
        
        // Load Groups in Background to prevent UI freeze
        Task.detached(priority: .userInitiated) {
            // We need a thread-safe way to get the playlist URL.
            // Since we can't access repository on background easily without isolation,
            // we assume the main repo has the data or we fetch via a new context if needed.
            // For simplicity/safety, we'll ask for the URL on MainActor then detach.
            
            let playlistUrl = await self.getLivePlaylistUrl()
            guard let plUrl = playlistUrl else {
                await MainActor.run { self.isLoading = false }
                return
            }
            
            // Create a background context to fetch groups efficiently
            // (Assuming Repository exposes a way to get a bg context, or we construct a simple fetch)
            // Ideally, we ask the Repository to do this work.
            let rawGroups = await self.repository?.getGroups(playlistUrl: plUrl, type: .live) ?? []
            
            // Filter and Sort
            let cleanGroups = rawGroups.filter { !$0.isEmpty && $0 != "Uncategorized" }.sorted()
            
            await MainActor.run {
                self.allGroups = cleanGroups
                self.isLoading = false
            }
        }
    }
    
    private func getLivePlaylistUrl() -> String? {
        let playlists = repository?.getAllPlaylists() ?? []
        return playlists.first(where: { $0.source == DataSourceType.xtream.rawValue || $0.source == DataSourceType.m3u.rawValue })?.url
    }
    
    private func refreshLists() {
        guard let repo = repository else { return }
        
        Task {
            // 1. Favorites
            let favs = repo.getFavorites(type: "live")
            
            // 2. Recently Watched
            let recents = repo.getSmartContinueWatching(type: "live")
            let limitedRecents = Array(recents.prefix(20))
            
            await MainActor.run {
                self.favoriteChannels = favs
                self.recentChannels = limitedRecents
            }
            
            // 3. Queue EPG Refresh
            let combined = (favs + limitedRecents)
            queueEpgRefresh(for: combined)
        }
    }
    
    // MARK: - Lazy Loading & EPG
    
    func onCategoryAppeared(category: String) {
        // Only load if not already present
        guard channelsByGroup[category] == nil else { return }
        
        Task {
            guard let repo = repository, let plUrl = getLivePlaylistUrl() else { return }
            
            // Fetch channels
            let channels = repo.getBrowsingContent(playlistUrl: plUrl, type: "live", group: category)
            
            await MainActor.run {
                self.channelsByGroup[category] = channels
            }
            
            // Queue EPG
            queueEpgRefresh(for: channels)
        }
    }
    
    // MARK: - Optimized EPG Batching
    // Fixes crash/stutter during fast scrolling by grouping API calls
    
    func onChannelFocused(_ channel: Channel) {
        queueEpgRefresh(for: [channel])
    }
    
    private func queueEpgRefresh(for channels: [Channel]) {
        for ch in channels {
            epgRefreshQueue.insert(ch)
        }
    }
    
    private func startEpgBatcher() {
        epgTimer?.invalidate()
        // Process queue every 1.5 seconds
        epgTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.processEpgQueue()
            }
        }
    }
    
    private func processEpgQueue() {
        guard !epgRefreshQueue.isEmpty, let service = epgService else { return }
        
        // Take a batch
        let batch = Array(epgRefreshQueue.prefix(20)) // Limit to 20 per cycle
        epgRefreshQueue.subtract(batch)
        
        Task {
            // 1. Fetch remote data
            await service.refreshEpg(for: batch)
            
            // 2. Update local UI map
            let freshMap = service.getCurrentPrograms(for: batch)
            
            await MainActor.run {
                for (key, value) in freshMap {
                    self.currentPrograms[key] = value
                }
            }
        }
    }
    
    // MARK: - Actions & Helpers
    
    func toggleFavorite(_ channel: Channel) {
        repository?.toggleFavorite(channel)
        // refreshLists() is triggered automatically via listener
    }
    
    func getProgram(for channel: Channel) -> Programme? {
        return currentPrograms[channel.url]
    }
    
    func getProgress(for channel: Channel) -> Double {
        guard let program = currentPrograms[channel.url] else { return 0.0 }
        
        let now = Date().timeIntervalSince1970
        let start = program.start.timeIntervalSince1970
        let end = program.end.timeIntervalSince1970
        
        if end <= start { return 0 } // Prevent division by zero
        if currentPrograms[channel.url] == nil { return 0 }
        
        if now < start { return 0 }
        if now > end { return 1 }
        
        return (now - start) / (end - start)
    }
}
