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
    
    // FIXED: Changed from 'private' to internal so ViewModels can access context for history checks
    let container: NSPersistentContainer
    
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
                
                // 1. Try Fast Sync (Bulk)
                do {
                    try await syncXtreamBulk(input: input, playlistUrl: playlistUrl)
                } catch {
                    // Check for Firewall/Rate Limit Errors
                    if let xErr = error as? XtreamError, case .invalidResponse(let code, _) = xErr, [512, 513, 504].contains(code) {
                        print("⚠️ Bulk Sync Failed (\(code)). Switching to Deep Sync (Safe Mode)...")
                        self.syncStatusMessage = "Switching to Deep Sync..."
                        // 2. Fallback to Slow Sync (Categories)
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
        
        // 1. Deep Sync Live
        self.syncStatusMessage = "Fetching Categories..."
        let liveCats = try await xtreamClient.getLiveCategories(input: input)
        
        for (index, cat) in liveCats.enumerated() {
            let status = "Live: \(cat.categoryName) (\(index + 1)/\(liveCats.count))"
            self.syncStatusMessage = status
            
            do {
                let streams = try await xtreamClient.getLiveStreams(input: input, categoryId: cat.categoryId)
                if !streams.isEmpty {
                    await saveBatch(items: streams.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) })
                }
                // 0.5s delay to be safe against 513 errors
                try? await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                print("⚠️ Failed category \(cat.categoryName): \(error.localizedDescription)")
            }
        }
        
        // 2. Deep Sync VOD
        self.syncStatusMessage = "Fetching Movie Categories..."
        let vodCats = try await xtreamClient.getVodCategories(input: input)
        
        for (index, cat) in vodCats.enumerated() {
            let status = "Mov: \(cat.categoryName) (\(index + 1)/\(vodCats.count))"
            self.syncStatusMessage = status
            
            do {
                let streams = try await xtreamClient.getVodStreams(input: input, categoryId: cat.categoryId)
                if !streams.isEmpty {
                    await saveBatch(items: streams.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) })
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                print("⚠️ Failed category \(cat.categoryName): \(error.localizedDescription)")
            }
        }
        
        // 3. Series
        self.syncStatusMessage = "Fetching Series..."
        do {
            let series = try await xtreamClient.getSeries(input: input)
            await saveBatch(items: series.map { ChannelStruct.from($0, playlistUrl: playlistUrl) })
        } catch {
            print("⚠️ Series Bulk failed in Deep Sync. Skipping Series.")
        }
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
    
    // FIXED: Added wrapper to expose version finding logic to ViewModels
    func getVersions(for channel: Channel) -> [Channel] {
        return channelRepo.getVersions(for: channel)
    }
    
    func getGroups(playlistUrl: String, type: StreamType) -> [String] {
        return channelRepo.getGroups(playlistUrl: playlistUrl, type: type.rawValue)
    }
    
    func getBrowsingContent(playlistUrl: String, type: StreamType, group: String) -> [Channel] {
        return channelRepo.getBrowsingContent(playlistUrl: playlistUrl, type: type.rawValue, group: group)
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
