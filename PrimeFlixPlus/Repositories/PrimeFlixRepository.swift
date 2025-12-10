import Foundation
import CoreData
import Combine
import SwiftUI

// MARK: - Sync Statistics Model
struct SyncStats {
    var moviesAdded: Int = 0
    var seriesAdded: Int = 0
    var liveChannelsAdded: Int = 0
    var totalProcessed: Int = 0
    var currentStage: String = "Initializing..."
    
    var totalItems: Int { moviesAdded + seriesAdded + liveChannelsAdded }
}

@MainActor
class PrimeFlixRepository: ObservableObject {
    
    // --- State ---
    @Published var isSyncing: Bool = false
    @Published var isInitialSync: Bool = false
    @Published var syncStatusMessage: String? = nil
    @Published var lastSyncDate: Date? = nil
    @Published var isErrorState: Bool = false
    @Published var syncStats: SyncStats = SyncStats()
    
    // The Container is exposed as internal so Services/ViewModels can use newBackgroundContext()
    internal let container: NSPersistentContainer
    
    // --- Internal Data Access ---
    // We keep a MainActor reference to the ChannelRepository for quick UI thread fetches
    private let channelRepo: ChannelRepository
    
    // --- Services & Engines ---
    private let xtreamClient = XtreamClient()
    private let tmdbClient = TmdbClient()
    
    // Lazy initialization of workers (Services)
    private lazy var syncEngine: SyncEngine = {
        return SyncEngine(container: container, xtreamClient: xtreamClient)
    }()
    
    // Dedicated Background Service for Bulk Updates
    private lazy var enrichmentService: EnrichmentService = {
        return EnrichmentService(context: container.newBackgroundContext(), tmdbClient: tmdbClient)
    }()
    
    init(container: NSPersistentContainer) {
        self.container = container
        // Initialize the DAO on the main context for UI operations
        self.channelRepo = ChannelRepository(context: container.viewContext)
    }
    
    // MARK: - Discovery and Search (CRITICAL PASSTHROUGH FUNCTIONS)

    /// Delegates the hybrid search logic to ChannelRepository using a dedicated background context.
    /// This method is called by SearchViewModel to run the fuzzy and filtered search.
    func searchHybrid(query: String, filters: ChannelRepository.SearchFilters) async -> ChannelRepository.SearchResults {
        // Run the entire fetch and ranking operation on a detached background task.
        return await Task.detached(priority: .userInitiated) {
            let bgContext = self.container.newBackgroundContext()
            let readRepo = ChannelRepository(context: bgContext)
            
            return readRepo.searchHybrid(query: query, filters: filters)
        }.value
    }
    
    /// Delegates the reverse search logic (finding local matches for external API titles).
    func findMatches(for titles: [String], limit: Int = 20) async -> [Channel] {
        return await Task.detached(priority: .utility) {
            let bgContext = self.container.newBackgroundContext()
            let readRepo = ChannelRepository(context: bgContext)
            return readRepo.findMatches(for: titles, limit: limit)
        }.value
    }
    
    // MARK: - Active Enrichment (NEW)
    
    /// Triggers an immediate metadata fetch for specific items (e.g. Search Results).
    /// Safe to call from Main Actor; handles thread confinement automatically.
    func enrichContent(items: [Channel]) async {
        guard !items.isEmpty else { return }
        
        // 1. Extract IDs on Main Thread to pass safely across boundaries
        let objectIDs = items.map { $0.objectID }
        
        // 2. Perform work on Background Thread
        await Task.detached(priority: .background) {
            let bgContext = self.container.newBackgroundContext()
            // Important: Use merge policy to handle potential conflicts during save
            bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            // 3. Re-fetch objects in the correct context
            // 'existingObject' is safer than 'object(with:)' as it ensures the data exists
            let bgItems = objectIDs.compactMap { try? bgContext.existingObject(with: $0) as? Channel }
            
            guard !bgItems.isEmpty else { return }
            
            // 4. Create a temporary service instance bound to this context
            let service = EnrichmentService(context: bgContext, tmdbClient: self.tmdbClient)
            
            // 5. Run Enrichment
            // We ignore status callbacks for search enrichment to keep UI clean
            await service.enrichLibrary(specificItems: bgItems, onStatus: { _ in })
            
        }.value
    }

    // MARK: - Core CRUD / Sync (Main Passthroughs)
    
    func getFavorites(type: String) -> [Channel] {
        return channelRepo.getFavorites(type: type)
    }
    
    func getRecentlyAdded(type: String, limit: Int) -> [Channel] {
        return channelRepo.getRecentlyAdded(type: type, limit: limit)
    }
    
    func getRecentFallback(type: String, limit: Int) -> [Channel] {
        return channelRepo.getRecentFallback(type: type, limit: limit)
    }
    
    func getSmartContinueWatching(type: String) -> [Channel] {
        return channelRepo.getSmartContinueWatching(type: type)
    }
    
    func getRecommended(type: String) -> [Channel] {
        // We use the viewContext safely since RecommendationService often reuses the context
        let service = RecommendationService(context: container.viewContext)
        return service.getRecommended(type: type)
    }
    
    func getGroups(playlistUrl: String, type: StreamType) -> [String] {
        return channelRepo.getGroups(playlistUrl: playlistUrl, type: type.rawValue)
    }
    
    func getBrowsingContent(playlistUrl: String, type: StreamType, group: String) -> [Channel] {
        // Corrected type conversion if necessary, assuming repository expects String
        return channelRepo.getBrowsingContent(playlistUrl: playlistUrl, type: type.rawValue, group: group)
    }
    
    // Overload for string type if needed by legacy code
    func getBrowsingContent(playlistUrl: String, type: String, group: String) -> [Channel] {
        return channelRepo.getBrowsingContent(playlistUrl: playlistUrl, type: type, group: group)
    }
    
    func getVersions(for channel: Channel) -> [Channel] {
        // Instantiate service on the fly for the UI thread
        let service = VersioningService(context: container.viewContext)
        return service.getVersions(for: channel)
    }

    // MARK: - Playlist Management
    
    func getAllPlaylists() -> [Playlist] {
        let request = NSFetchRequest<Playlist>(entityName: "Playlist")
        return (try? container.viewContext.fetch(request)) ?? []
    }
    
    func addPlaylist(title: String, url: String, source: DataSourceType) {
        let context = container.viewContext
        let req = NSFetchRequest<Playlist>(entityName: "Playlist")
        req.predicate = NSPredicate(format: "url == %@", url)
        
        if (try? context.fetch(req).count) ?? 0 == 0 {
            _ = Playlist(context: context, title: title, url: url, source: source)
            try? context.save()
            
            // Trigger Sync automatically
            Task.detached(priority: .userInitiated) {
                await self.syncPlaylistWrapper(playlistTitle: title, playlistUrl: url, source: source, force: true, isFirstTime: true)
            }
        }
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        let context = container.viewContext
        let plUrl = playlist.url
        
        // 1. Delete Channels (Batch)
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
        fetch.predicate = NSPredicate(format: "playlistUrl == %@", plUrl)
        let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
        _ = try? context.execute(deleteReq)
        
        // 2. Delete Playlist Entity
        context.delete(playlist)
        try? context.save()
        
        // 3. Clear Cache Timestamp
        UserDefaults.standard.removeObject(forKey: "last_sync_\(plUrl)")
        
        self.objectWillChange.send()
    }
    
    // MARK: - Sync Orchestration
    
    func syncAll(force: Bool = false) async {
        guard !isSyncing else { return }
        let playlists = getAllPlaylists()
        guard !playlists.isEmpty else { return }
        
        self.isSyncing = true
        self.isErrorState = false
        self.syncStats = SyncStats() // Reset stats
        
        await Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            for playlist in playlists {
                guard let source = DataSourceType(rawValue: playlist.source) else { continue }
                await self.syncPlaylistWrapper(playlistTitle: playlist.title, playlistUrl: playlist.url, source: source, force: force, isFirstTime: false)
            }
            
            await MainActor.run {
                if !self.isErrorState {
                    if force || self.syncStatusMessage != nil {
                        self.syncStatusMessage = "Sync Complete"
                    }
                    self.lastSyncDate = Date()
                    self.isInitialSync = false
                    
                    // Clear toast after delay
                    Task {
                        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                        self.syncStatusMessage = nil
                        self.isSyncing = false
                    }
                } else {
                    self.isSyncing = false
                }
            }
        }.value
    }
    
    /// Wrapper that bridges the SyncEngine (Background) with the Repository State (Main Actor).
    private nonisolated func syncPlaylistWrapper(playlistTitle: String, playlistUrl: String, source: DataSourceType, force: Bool, isFirstTime: Bool) async {
        
        await MainActor.run {
            self.syncStatusMessage = isFirstTime ? "Setting up \(playlistTitle)..." : "Checking for updates..."
            if isFirstTime { self.isInitialSync = true }
        }
        
        // Retrieve a thread-safe reference to the playlist data via a temporary background context
        let bgContext = container.newBackgroundContext()
        var bgPlaylist: Playlist?
        bgContext.performAndWait {
            let req = NSFetchRequest<Playlist>(entityName: "Playlist")
            req.predicate = NSPredicate(format: "url == %@", playlistUrl)
            bgPlaylist = try? bgContext.fetch(req).first
        }
        
        guard let pl = bgPlaylist else { return }
        
        do {
            // Run the Sync Engine
            let hasChanges = try await syncEngine.sync(
                playlist: pl,
                force: force,
                onStatus: { msg in
                    Task { @MainActor in self.syncStatusMessage = msg }
                },
                onStats: { stats in
                    Task { @MainActor in self.syncStats = stats }
                }
            )
            
            // Run Enrichment if needed (First time or content changed)
            if hasChanges || isFirstTime {
                await enrichmentService.enrichLibrary(
                    playlistUrl: playlistUrl,
                    onStatus: { msg in
                        Task { @MainActor in self.syncStatusMessage = msg }
                    }
                )
            }
            
        } catch {
            print("❌ Sync Failed: \(error.localizedDescription)")
            await MainActor.run {
                self.isErrorState = true
                // FIX: Propagate the actual error description to the UI so the user knows WHY it failed.
                self.syncStatusMessage = "Sync Error: \(error.localizedDescription)"
            }
        }
    }
    
    func nuclearResync(playlist: Playlist) async {
        guard let source = DataSourceType(rawValue: playlist.source) else { return }
        
        self.isSyncing = true
        self.isInitialSync = true
        self.syncStatusMessage = "Wiping Database..."
        self.syncStats = SyncStats()
        
        let bgContext = container.newBackgroundContext()
        await bgContext.perform {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
            fetch.predicate = NSPredicate(format: "playlistUrl == %@", playlist.url)
            let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
            
            _ = try? bgContext.execute(deleteReq)
            try? bgContext.save()
            bgContext.reset()
        }
        
        UserDefaults.standard.removeObject(forKey: "last_sync_\(playlist.url)")
        
        await Task.detached {
            await self.syncPlaylistWrapper(playlistTitle: playlist.title, playlistUrl: playlist.url, source: source, force: true, isFirstTime: true)
        }.value
    }
    
    // MARK: - Legacy Passthroughs
    
    func toggleFavorite(_ channel: Channel) {
        channelRepo.toggleFavorite(channel)
        try? container.viewContext.save()
        self.objectWillChange.send()
    }
    
    func saveProgress(url: String, pos: Int64, dur: Int64) {
        container.performBackgroundTask { [weak self] context in
            let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            request.predicate = NSPredicate(format: "channelUrl == %@", url)
            
            let progress: WatchProgress
            if let result = (try? context.fetch(request))?.first {
                progress = result
            } else {
                progress = WatchProgress(context: context, channelUrl: url, position: pos, duration: dur)
            }
            
            progress.position = pos
            progress.duration = dur
            progress.lastPlayed = Date()
            
            try? context.save()
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }
}
