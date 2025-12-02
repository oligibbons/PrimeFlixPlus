import Foundation
import CoreData
import Combine

@MainActor
class PrimeFlixRepository: ObservableObject {
    
    private let container: NSPersistentContainer
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    private let channelRepo: ChannelRepository
    
    init(container: NSPersistentContainer) {
        self.container = container
        self.channelRepo = ChannelRepository(context: container.viewContext)
    }
    
    // MARK: - Playlist
    func getAllPlaylists() -> [Playlist] {
        let request: NSFetchRequest<Playlist> = NSFetchRequest(entityName: "Playlist")
        return (try? container.viewContext.fetch(request)) ?? []
    }
    
    func addPlaylist(title: String, url: String, source: DataSourceType) {
        let context = container.viewContext
        _ = Playlist(context: context, title: title, url: url, source: source)
        try? context.save()
        
        Task { await syncPlaylist(playlistTitle: title, playlistUrl: url, source: source) }
    }
    
    // MARK: - Sync Logic
    func syncPlaylist(playlistTitle: String, playlistUrl: String, source: DataSourceType) async {
        print("Syncing: \(playlistTitle)")
        
        // 1. Delete Old Data
        await container.performBackgroundTask { context in
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
            fetch.predicate = NSPredicate(format: "playlistUrl == %@", playlistUrl)
            let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
            _ = try? context.execute(deleteReq)
        }
        
        // 2. Fetch & Parse
        var channels: [ChannelStruct] = []
        
        if source == .xtream {
            let input = XtreamInput.decodeFromPlaylistUrl(playlistUrl)
            if let live = try? await xtreamClient.getLiveStreams(input: input) {
                channels += live.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
            }
            if let vod = try? await xtreamClient.getVodStreams(input: input) {
                channels += vod.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
            }
        } else if source == .m3u {
            guard let url = URL(string: playlistUrl) else { return }
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let content = String(data: data, encoding: .utf8) {
                channels = await M3UParser.parse(content: content, playlistUrl: playlistUrl)
            }
        }
        
        // 3. Batch Insert
        if !channels.isEmpty {
            await container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                for item in channels {
                    _ = item.toManagedObject(context: context)
                }
                try? context.save()
            }
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Accessors
    func getGroups(playlistUrl: String, type: StreamType) -> [String] {
        return channelRepo.getGroups(playlistUrl: playlistUrl, type: type.rawValue)
    }
    
    func getBrowsingContent(playlistUrl: String, type: StreamType, group: String) -> [Channel] {
        // Call the new method in ChannelRepository directly
        return channelRepo.getBrowsingContent(playlistUrl: playlistUrl, type: type.rawValue, group: group)
    }
    
    func getRecentAdded(playlistUrl: String, type: StreamType) -> [Channel] {
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = 20
        return (try? container.viewContext.fetch(request)) ?? []
    }
    
    func getFavorites() -> [Channel] {
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        request.predicate = NSPredicate(format: "isFavorite == YES")
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
