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
    @Published var channelsByGroup: [String: [Channel]] = [:]
    
    // EPG Data (Map: Channel URL -> Current Program)
    @Published var currentPrograms: [String: Programme] = [:]
    @Published var isLoading: Bool = true
    
    // Navigation & Selection
    @Published var selectedCategory: String? = nil
    
    // Dependencies
    private var repository: PrimeFlixRepository?
    private var epgService: EpgService?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.epgService = EpgService(context: repository.container.viewContext)
        
        loadData()
        setupListeners()
        
        // Periodic EPG Cleanup (remove old programs every 10 mins)
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.epgService?.pruneExpiredPrograms() }
        }
    }
    
    private func setupListeners() {
        // Refresh when favorites or history change
        repository?.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshLists() }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    
    func loadData() {
        self.isLoading = true
        refreshLists()
        
        // Load All Groups/Channels for the Grid
        Task {
            guard let repo = repository else { return }
            
            // 1. Get Live Playlist (Assuming active one)
            let playlist = repo.getAllPlaylists().first(where: { $0.source == DataSourceType.xtream.rawValue || $0.source == DataSourceType.m3u.rawValue })
            guard let plUrl = playlist?.url else { return }
            
            // 2. Fetch Groups
            let rawGroups = repo.getGroups(playlistUrl: plUrl, type: .live)
            // Filter empty or junk groups
            let cleanGroups = rawGroups.filter { !$0.isEmpty && $0 != "Uncategorized" }.sorted()
            
            self.allGroups = cleanGroups
            self.isLoading = false
        }
    }
    
    private func refreshLists() {
        guard let repo = repository else { return }
        
        // 1. Favorites
        self.favoriteChannels = repo.getFavorites(type: "live")
        
        // 2. Recently Watched (Specific logic for Live TV)
        // We use 'getSmartContinueWatching' but filter strictly for Live items
        let recents = repo.getSmartContinueWatching(type: "live")
        self.recentChannels = Array(recents.prefix(20))
        
        // 3. Trigger EPG Refresh for these "Top Shelf" items
        let combined = (favoriteChannels + recentChannels)
        if !combined.isEmpty {
            updateEpg(for: combined)
        }
    }
    
    // MARK: - EPG Logic
    
    /// Called when a row/category receives focus or becomes visible
    func onCategoryAppeared(category: String) {
        // If we haven't loaded channels for this group yet, do it now (Lazy Loading)
        if channelsByGroup[category] == nil {
            Task {
                guard let repo = repository, let pl = repo.getAllPlaylists().first else { return }
                let channels = repo.getBrowsingContent(playlistUrl: pl.url, type: "live", group: category)
                
                await MainActor.run {
                    self.channelsByGroup[category] = channels
                    // Fetch EPG for this batch
                    self.updateEpg(for: channels)
                }
            }
        }
    }
    
    /// Called when a specific channel is focused (High Priority EPG fetch)
    func onChannelFocused(_ channel: Channel) {
        updateEpg(for: [channel])
    }
    
    private func updateEpg(for channels: [Channel]) {
        guard let service = epgService, !channels.isEmpty else { return }
        
        Task {
            // 1. Fetch remote data (if stale)
            await service.refreshEpg(for: channels)
            
            // 2. Update local UI map
            let freshMap = service.getCurrentPrograms(for: channels)
            
            await MainActor.run {
                // Merge into existing map
                self.currentPrograms.merge(freshMap) { (_, new) in new }
            }
        }
    }
    
    // MARK: - Actions
    
    func toggleFavorite(_ channel: Channel) {
        repository?.toggleFavorite(channel)
        // Listener will auto-refresh lists
    }
    
    func getProgram(for channel: Channel) -> Programme? {
        return currentPrograms[channel.url]
    }
    
    /// Calculates progress (0.0 - 1.0) for the current program
    func getProgress(for program: Programme) -> Double {
        let now = Date()
        let start = program.start.timeIntervalSince1970
        let end = program.end.timeIntervalSince1970
        let current = now.timeIntervalSince1970
        
        if current < start { return 0 }
        if current > end { return 1 }
        
        let total = end - start
        if total <= 0 { return 0 }
        
        return (current - start) / total
    }
}
