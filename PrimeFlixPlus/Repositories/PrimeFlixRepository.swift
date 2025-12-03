import Foundation
import CoreData
import Combine

@MainActor
class PrimeFlixRepository: ObservableObject {
    
    @Published var isSyncing: Bool = false
    @Published var syncStatusMessage: String? = nil
    @Published var lastSyncDate: Date? = nil
    @Published var isErrorState: Bool = false
    
    private let container: NSPersistentContainer
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    private let channelRepo: ChannelRepository
    
    init(container: NSPersistentContainer) {
        self.container = container
        self.channelRepo = ChannelRepository(context: container.viewContext)
    }
    
    // MARK: - Playlist Management
    func getAllPlaylists() -> [Playlist] {
        let request: NSFetchRequest<Playlist> = NSFetchRequest(entityName: "Playlist")
        return (try? container.viewContext.fetch(request)) ?? []
    }
    
    func addPlaylist(title: String, url: String, source: DataSourceType) {
        let context = container.viewContext
        let req: NSFetchRequest<Playlist> = NSFetchRequest(entityName: "Playlist")
        req.predicate = NSPredicate(format: "url == %@", url)
        
        if (try? context.fetch(req).count) ?? 0 == 0 {
            _ = Playlist(context: context, title: title, url: url, source: source)
            try? context.save()
            Task { await syncPlaylist(playlistTitle: title, playlistUrl: url, source: source) }
        }
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        let context = container.viewContext
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
        fetch.predicate = NSPredicate(format: "playlistUrl == %@", playlist.url)
        let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
        _ = try? context.execute(deleteReq)
        
        context.delete(playlist)
        try? context.save()
        self.objectWillChange.send()
    }
    
    // MARK: - Sync Logic
    func syncAll() async {
        guard !isSyncing else { return }
        let playlists = getAllPlaylists()
        guard !playlists.isEmpty else { return }
        
        self.isSyncing = true
        self.isErrorState = false
        self.syncStatusMessage = "Starting Auto-Sync..."
        
        for playlist in playlists {
            guard let source = DataSourceType(rawValue: playlist.source) else { continue }
            await syncPlaylist(playlistTitle: playlist.title, playlistUrl: playlist.url, source: source, isAutoSync: true)
        }
        
        self.isSyncing = false
        if !self.isErrorState {
            self.syncStatusMessage = "Sync Complete"
            self.lastSyncDate = Date()
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            self.syncStatusMessage = nil
        }
    }
    
    func syncPlaylist(playlistTitle: String, playlistUrl: String, source: DataSourceType, isAutoSync: Bool = false) async {
        if !isAutoSync {
            self.isSyncing = true
            self.isErrorState = false
        }
        
        self.syncStatusMessage = "Connecting..."
        
        // Clean old data for this playlist
        await container.performBackgroundTask { context in
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
            fetch.predicate = NSPredicate(format: "playlistUrl == %@", playlistUrl)
            let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
            _ = try? context.execute(deleteReq)
            try? context.save()
        }
        
        var channels: [ChannelStruct] = []
        var hasAnySuccess = false
        
        do {
            if source == .xtream {
                let input = XtreamInput.decodeFromPlaylistUrl(playlistUrl)
                
                // Live
                self.syncStatusMessage = "Fetching Live..."
                do {
                    let live = try await xtreamClient.getLiveStreams(input: input)
                    channels += live.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
                    hasAnySuccess = true
                } catch {
                    print("⚠️ Live Skipped: \(error.localizedDescription)")
                }
                
                // VOD
                self.syncStatusMessage = "Fetching Movies..."
                do {
                    let vod = try await xtreamClient.getVodStreams(input: input)
                    channels += vod.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
                    hasAnySuccess = true
                } catch {
                    print("⚠️ VOD Skipped: \(error.localizedDescription)")
                }
                
                // Series
                self.syncStatusMessage = "Fetching Series..."
                do {
                    let series = try await xtreamClient.getSeries(input: input)
                    channels += series.map { ChannelStruct.from($0, playlistUrl: playlistUrl) }
                    hasAnySuccess = true
                } catch {
                     print("⚠️ Series Skipped: \(error.localizedDescription)")
                }
                
                // If EVERYTHING failed, we force a hard error by trying one call again
                if !hasAnySuccess {
                    _ = try await xtreamClient.getLiveStreams(input: input)
                }
                
            } else if source == .m3u {
                self.syncStatusMessage = "Downloading M3U..."
                guard let url = URL(string: playlistUrl) else { throw URLError(.badURL) }
                let (data, response) = try await UnsafeSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                if let content = String(data: data, encoding: .utf8) {
                    self.syncStatusMessage = "Parsing..."
                    channels = await M3UParser.parse(content: content, playlistUrl: playlistUrl)
                }
            }
            
            self.syncStatusMessage = "Saving \(channels.count) items..."
            if !channels.isEmpty {
                await container.performBackgroundTask { context in
                    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                    for (index, item) in channels.enumerated() {
                        _ = item.toManagedObject(context: context)
                        if index % 2000 == 0 { try? context.save() }
                    }
                    try? context.save()
                }
                await MainActor.run { self.objectWillChange.send() }
            }
            
            if !isAutoSync {
                self.syncStatusMessage = "Done"
                self.isSyncing = false
                self.lastSyncDate = Date()
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                self.syncStatusMessage = nil
            }
            
        } catch {
            print("❌ Sync Failed: \(error)")
            self.isErrorState = true
            self.isSyncing = false
            
            // Show the user WHY it failed
            if let xError = error as? XtreamError {
                self.syncStatusMessage = xError.errorDescription
            } else if let urlError = error as? URLError {
                self.syncStatusMessage = "Net Error: \(urlError.localizedDescription)"
            } else {
                self.syncStatusMessage = "Error: \(error.localizedDescription)"
            }
            
            try? await Task.sleep(nanoseconds: 6 * 1_000_000_000)
            self.syncStatusMessage = nil
            self.isErrorState = false
        }
    }
    
    // MARK: - Accessors
    func getGroups(playlistUrl: String, type: StreamType) -> [String] {
        return channelRepo.getGroups(playlistUrl: playlistUrl, type: type.rawValue)
    }
    
    func getBrowsingContent(playlistUrl: String, type: StreamType, group: String) -> [Channel] {
        return channelRepo.getBrowsingContent(playlistUrl: playlistUrl, type: type.rawValue, group: group)
    }
    
    func getRecentAdded(playlistUrl: String, type: StreamType) -> [Channel] {
        return repositoryFetch(predicate: NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type.rawValue), sort: [NSSortDescriptor(key: "addedAt", ascending: false)], limit: 20)
    }
    
    func getFavorites() -> [Channel] {
        return repositoryFetch(predicate: NSPredicate(format: "isFavorite == YES"))
    }
    
    private func repositoryFetch(predicate: NSPredicate? = nil, sort: [NSSortDescriptor]? = nil, limit: Int? = nil) -> [Channel] {
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = sort
        if let limit = limit { request.fetchLimit = limit }
        return (try? container.viewContext.fetch(request)) ?? []
    }
    
    func toggleFavorite(_ channel: Channel) {
        channelRepo.toggleFavorite(channel: channel)
        objectWillChange.send()
    }
    
    func saveProgress(url: String, pos: Int64, dur: Int64) {
        let context = container.viewContext
        let request: NSFetchRequest<WatchProgress> = NSFetchRequest(entityName: "WatchProgress")
        request.predicate = NSPredicate(format: "channelUrl == %@", url)
        
        let progress: WatchProgress = (try? context.fetch(request))?.first ?? WatchProgress(context: context, channelUrl: url, position: pos, duration: dur)
        progress.position = pos
        progress.duration = dur
        progress.lastPlayed = Date()
        try? context.save()
    }
}
