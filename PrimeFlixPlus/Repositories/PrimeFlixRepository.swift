import Foundation
import CoreData
import Combine
import SwiftUI

@MainActor
class PrimeFlixRepository: ObservableObject {
    
    @Published var isSyncing: Bool = false
    @Published var syncStatusMessage: String? = nil
    @Published var lastSyncDate: Date? = nil
    @Published var isErrorState: Bool = false
    
    // Internal access for ViewModels
    internal let container: NSPersistentContainer
    
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    private let channelRepo: ChannelRepository
    
    init(container: NSPersistentContainer) {
        self.container = container
        self.channelRepo = ChannelRepository(context: container.viewContext)
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
    
    // MARK: - Smart Accessors (Restored)
    
    func getSmartContinueWatching(type: String) -> [Channel] {
        return channelRepo.getSmartContinueWatching(type: type)
    }
    
    func getFavorites(type: String) -> [Channel] {
        return channelRepo.getFavorites(type: type)
    }
    
    func getRecentlyAdded(type: String, limit: Int) -> [Channel] {
        return channelRepo.getRecentlyAdded(type: type, limit: limit)
    }
    
    func getRecentFallback(type: String, limit: Int) -> [Channel] {
        return channelRepo.getRecentFallback(type: type, limit: limit)
    }
    
    func getByGenre(type: String, groupName: String, limit: Int) -> [Channel] {
        return channelRepo.getByGenre(type: type, groupName: groupName, limit: limit)
    }
    
    func getTrendingMatches(type: String, tmdbResults: [String]) -> [Channel] {
        return channelRepo.getTrendingMatches(type: type, tmdbResults: tmdbResults)
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
        
        await container.performBackgroundTask { context in
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
            fetch.predicate = NSPredicate(format: "playlistUrl == %@", playlistUrl)
            let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
            _ = try? context.execute(deleteReq)
            try? context.save()
        }
        
        do {
            if source == .xtream {
                let input = XtreamInput.decodeFromPlaylistUrl(playlistUrl)
                
                do {
                    try await syncXtreamBulk(input: input, playlistUrl: playlistUrl)
                } catch {
                    if let xErr = error as? XtreamError, case .invalidResponse(let code, _) = xErr, [512, 513, 504].contains(code) {
                        print("⚠️ Bulk Sync Failed (\(code)). Switching to Deep Sync...")
                        self.syncStatusMessage = "Switching to Deep Sync..."
                        try await syncXtreamByCategories(input: input, playlistUrl: playlistUrl)
                    } else {
                        throw error
                    }
                }
                
            } else if source == .m3u {
                try await syncM3U(playlistUrl: playlistUrl)
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
            self.syncStatusMessage = (error as? XtreamError)?.errorDescription ?? error.localizedDescription
            try? await Task.sleep(nanoseconds: 6 * 1_000_000_000)
            self.syncStatusMessage = nil
            self.isErrorState = false
        }
    }
    
    // MARK: - Xtream Strategies
    
    private func syncXtreamBulk(input: XtreamInput, playlistUrl: String) async throws {
        self.syncStatusMessage = "Fetching Live..."
        let live = try await xtreamClient.getLiveStreams(input: input)
        await saveBatch(items: live.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) })
        
        self.syncStatusMessage = "Fetching Movies..."
        let vod = try await xtreamClient.getVodStreams(input: input)
        await saveBatch(items: vod.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) })
        
        self.syncStatusMessage = "Fetching Series..."
        let series = try await xtreamClient.getSeries(input: input)
        await saveBatch(items: series.map { ChannelStruct.from($0, playlistUrl: playlistUrl) })
    }
    
    private func syncXtreamByCategories(input: XtreamInput, playlistUrl: String) async throws {
        let liveCats = try await xtreamClient.getLiveCategories(input: input)
        for (index, cat) in liveCats.enumerated() {
            self.syncStatusMessage = "Live: \(cat.categoryName) (\(index + 1)/\(liveCats.count))"
            let streams = try await xtreamClient.getLiveStreams(input: input, categoryId: cat.categoryId)
            if !streams.isEmpty {
                await saveBatch(items: streams.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) })
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        let vodCats = try await xtreamClient.getVodCategories(input: input)
        for (index, cat) in vodCats.enumerated() {
            self.syncStatusMessage = "Mov: \(cat.categoryName) (\(index + 1)/\(vodCats.count))"
            let streams = try await xtreamClient.getVodStreams(input: input, categoryId: cat.categoryId)
            if !streams.isEmpty {
                await saveBatch(items: streams.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) })
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        self.syncStatusMessage = "Fetching Series..."
        let series = try await xtreamClient.getSeries(input: input)
        await saveBatch(items: series.map { ChannelStruct.from($0, playlistUrl: playlistUrl) })
    }
    
    private func syncM3U(playlistUrl: String) async throws {
        self.syncStatusMessage = "Downloading M3U..."
        guard let url = URL(string: playlistUrl) else { throw URLError(.badURL) }
        let (data, response) = try await UnsafeSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        if let content = String(data: data, encoding: .utf8) {
            self.syncStatusMessage = "Parsing..."
            let channels = await M3UParser.parse(content: content, playlistUrl: playlistUrl)
            await saveBatch(items: channels)
        }
    }
    
    private func saveBatch(items: [ChannelStruct]) async {
        guard !items.isEmpty else { return }
        await container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            for item in items {
                _ = item.toManagedObject(context: context)
            }
            try? context.save()
        }
        await MainActor.run { self.objectWillChange.send() }
    }
    
    // MARK: - Accessors
    
    func getVersions(for channel: Channel) -> [Channel] {
        return channelRepo.getVersions(for: channel)
    }
    
    func getGroups(playlistUrl: String, type: StreamType) -> [String] {
        return channelRepo.getGroups(playlistUrl: playlistUrl, type: type.rawValue)
    }
    
    func getBrowsingContent(playlistUrl: String, type: String, group: String) -> [Channel] {
        return channelRepo.getBrowsingContent(playlistUrl: playlistUrl, type: type, group: group)
    }
    
    func getRecentAdded(playlistUrl: String, type: StreamType) -> [Channel] {
        return channelRepo.getRecentAdded(playlistUrl: playlistUrl, type: type.rawValue)
    }
    
    func getFavorites() -> [Channel] {
        return channelRepo.getFavorites()
    }
    
    func toggleFavorite(_ channel: Channel) {
        channelRepo.toggleFavorite(channel: channel)
        objectWillChange.send()
    }
    
    func saveProgress(url: String, pos: Int64, dur: Int64) {
        let context = container.viewContext
        let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        request.predicate = NSPredicate(format: "channelUrl == %@", url)
        
        let progress: WatchProgress = (try? context.fetch(request))?.first ?? WatchProgress(context: context, channelUrl: url, position: pos, duration: dur)
        progress.position = pos
        progress.duration = dur
        progress.lastPlayed = Date()
        try? context.save()
    }
}
