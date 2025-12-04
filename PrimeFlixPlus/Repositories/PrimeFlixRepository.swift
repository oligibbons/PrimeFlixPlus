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
    
    internal let container: NSPersistentContainer
    
    // Services
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    
    // Main Context Accessor (for UI binding)
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
            
            Task.detached(priority: .userInitiated) {
                await self.syncPlaylist(playlistTitle: title, playlistUrl: url, source: source)
            }
        }
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        let context = container.viewContext
        let plUrl = playlist.url
        
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
        fetch.predicate = NSPredicate(format: "playlistUrl == %@", plUrl)
        let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
        _ = try? context.execute(deleteReq)
        
        context.delete(playlist)
        try? context.save()
        self.objectWillChange.send()
    }
    
    // MARK: - Smart Accessors (Main Thread / UI)
    
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
    
    func getVersions(for channel: Channel) -> [Channel] {
        return channelRepo.getVersions(for: channel)
    }
    
    func getGroups(playlistUrl: String, type: StreamType) -> [String] {
        return channelRepo.getGroups(playlistUrl: playlistUrl, type: type.rawValue)
    }
    
    func getBrowsingContent(playlistUrl: String, type: String, group: String) -> [Channel] {
        return channelRepo.getBrowsingContent(playlistUrl: playlistUrl, type: type, group: group)
    }
    
    func toggleFavorite(_ channel: Channel) {
        channelRepo.toggleFavorite(channel: channel)
        self.objectWillChange.send()
    }
    
    func saveProgress(url: String, pos: Int64, dur: Int64) {
        container.performBackgroundTask { context in
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
        }
    }
    
    // MARK: - Thread-Safe / Background Accessors (New)
    
    /// Fetches trending matches on a background context to avoid blocking the Main Thread
    nonisolated func getTrendingMatchesAsync(type: String, tmdbResults: [String]) async -> [NSManagedObjectID] {
        await container.performBackgroundTask { context in
            var matches: [NSManagedObjectID] = []
            var seenTitles = Set<String>()
            
            for title in tmdbResults {
                let req = NSFetchRequest<Channel>(entityName: "Channel")
                req.predicate = NSPredicate(format: "type == %@ AND title CONTAINS[cd] %@", type, title)
                req.fetchLimit = 1
                
                if let match = try? context.fetch(req).first {
                    let norm = TitleNormalizer.parse(rawTitle: match.title).normalizedTitle
                    if !seenTitles.contains(norm) {
                        matches.append(match.objectID)
                        seenTitles.insert(norm)
                    }
                }
            }
            return matches
        }
    }
    
    // MARK: - Smart Sync Logic
    
    func syncAll() async {
        guard !isSyncing else { return }
        let playlists = getAllPlaylists()
        guard !playlists.isEmpty else { return }
        
        self.isSyncing = true
        self.isErrorState = false
        self.syncStatusMessage = "Syncing Library..."
        
        await Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            for playlist in playlists {
                guard let source = DataSourceType(rawValue: playlist.source) else { continue }
                await self.syncPlaylist(playlistTitle: playlist.title, playlistUrl: playlist.url, source: source, isAutoSync: true)
            }
            
            await MainActor.run {
                if !self.isErrorState {
                    self.syncStatusMessage = "Sync Complete"
                    self.lastSyncDate = Date()
                    Task {
                        try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                        self.syncStatusMessage = nil
                        self.isSyncing = false
                    }
                } else {
                    self.isSyncing = false
                }
            }
        }.value
    }
    
    nonisolated func syncPlaylist(playlistTitle: String, playlistUrl: String, source: DataSourceType, isAutoSync: Bool = false) async {
        
        await MainActor.run {
            if !isAutoSync {
                self.isSyncing = true
                self.isErrorState = false
            }
            self.syncStatusMessage = "Connecting..."
        }
        
        // 1. Snapshot existing content to avoid duplicates (Smart Sync)
        var existingUrls = Set<String>()
        let context = container.newBackgroundContext()
        context.performAndWait {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
            req.predicate = NSPredicate(format: "playlistUrl == %@", playlistUrl)
            req.propertiesToFetch = ["url"]
            req.resultType = .dictionaryResultType
            
            if let results = try? context.fetch(req) as? [[String: String]] {
                existingUrls = Set(results.compactMap { $0["url"] })
            }
        }
        
        var processedUrls = Set<String>()
        
        do {
            if source == .xtream {
                let input = XtreamInput.decodeFromPlaylistUrl(playlistUrl)
                
                do {
                    // Try Bulk Sync (optimized with exclusion set)
                    let newUrls = try await syncXtreamBulk(input: input, playlistUrl: playlistUrl, existing: existingUrls)
                    processedUrls.formUnion(newUrls)
                } catch {
                    // Fallback to Category Sync
                    if let xErr = error as? XtreamError, case .invalidResponse(let code, _) = xErr, [512, 513, 504].contains(code) {
                        await MainActor.run { self.syncStatusMessage = "Deep Sync (Safe Mode)..." }
                        let newUrls = try await syncXtreamByCategories(input: input, playlistUrl: playlistUrl, existing: existingUrls)
                        processedUrls.formUnion(newUrls)
                    } else {
                        throw error
                    }
                }
                
            } else if source == .m3u {
                let newUrls = try await syncM3U(playlistUrl: playlistUrl) // M3U usually overwrites or simpler logic
                processedUrls.formUnion(newUrls)
            }
            
            // 2. Orphan Deletion (Only remove items that are TRULY gone)
            // Note: If we skipped them because they existed, they are in `existing` but not returned as "new" by helpers
            // So we need to track *verified* URLs.
            // For Smart Sync: We must assume that if we fetched it, it's verified.
            // In the helpers below, I return `processedUrls` which should include BOTH new AND existing items found in the feed.
            
            let orphans = existingUrls.subtracting(processedUrls)
            if !orphans.isEmpty {
                await deleteOrphans(urls: Array(orphans), playlistUrl: playlistUrl)
            }
            
            if !isAutoSync {
                await MainActor.run {
                    self.syncStatusMessage = "Done"
                    self.lastSyncDate = Date()
                    Task {
                        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                        self.syncStatusMessage = nil
                        self.isSyncing = false
                    }
                }
            }
            
        } catch {
            print("❌ Sync Failed: \(error)")
            await MainActor.run {
                self.isErrorState = true
                self.isSyncing = false
                self.syncStatusMessage = "Sync Failed"
                Task {
                    try? await Task.sleep(nanoseconds: 6 * 1_000_000_000)
                    self.syncStatusMessage = nil
                    self.isErrorState = false
                }
            }
        }
    }
    
    // MARK: - Sync Helpers (Smart)
    
    private func syncXtreamBulk(input: XtreamInput, playlistUrl: String, existing: Set<String>) async throws -> Set<String> {
        var verified = Set<String>()
        
        // Live
        await MainActor.run { self.syncStatusMessage = "Checking Live..." }
        let live = try await xtreamClient.getLiveStreams(input: input)
        // Add all found to verified list
        let liveStructs = live.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
        verified.formUnion(liveStructs.map { $0.url })
        // Only save what we don't have
        let newLive = liveStructs.filter { !existing.contains($0.url) }
        await saveBatch(items: newLive)
        
        // Movies
        await MainActor.run { self.syncStatusMessage = "Checking Movies..." }
        let vod = try await xtreamClient.getVodStreams(input: input)
        let vodStructs = vod.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
        verified.formUnion(vodStructs.map { $0.url })
        let newVod = vodStructs.filter { !existing.contains($0.url) }
        await saveBatch(items: newVod)
        
        // Series
        await MainActor.run { self.syncStatusMessage = "Checking Series..." }
        let series = try await xtreamClient.getSeries(input: input)
        let seriesStructs = series.map { ChannelStruct.from($0, playlistUrl: playlistUrl) }
        verified.formUnion(seriesStructs.map { $0.url })
        let newSeries = seriesStructs.filter { !existing.contains($0.url) }
        await saveBatch(items: newSeries)
        
        return verified
    }
    
    private func syncXtreamByCategories(input: XtreamInput, playlistUrl: String, existing: Set<String>) async throws -> Set<String> {
        var verified = Set<String>()
        
        // Live
        let liveCats = try await xtreamClient.getLiveCategories(input: input)
        for (index, cat) in liveCats.enumerated() {
            await MainActor.run { self.syncStatusMessage = "Live: \(cat.categoryName) (\(index + 1)/\(liveCats.count))" }
            if let streams = try? await xtreamClient.getLiveStreams(input: input, categoryId: cat.categoryId) {
                let structs = streams.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
                verified.formUnion(structs.map { $0.url })
                let newItems = structs.filter { !existing.contains($0.url) }
                await saveBatch(items: newItems)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        
        // VOD
        let vodCats = try await xtreamClient.getVodCategories(input: input)
        for (index, cat) in vodCats.enumerated() {
            await MainActor.run { self.syncStatusMessage = "Mov: \(cat.categoryName) (\(index + 1)/\(vodCats.count))" }
            if let streams = try? await xtreamClient.getVodStreams(input: input, categoryId: cat.categoryId) {
                let structs = streams.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
                verified.formUnion(structs.map { $0.url })
                let newItems = structs.filter { !existing.contains($0.url) }
                await saveBatch(items: newItems)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        
        // Series (Bulk fallback for series usually safe)
        if let series = try? await xtreamClient.getSeries(input: input) {
            let structs = series.map { ChannelStruct.from($0, playlistUrl: playlistUrl) }
            verified.formUnion(structs.map { $0.url })
            let newItems = structs.filter { !existing.contains($0.url) }
            await saveBatch(items: newItems)
        }
        
        return verified
    }
    
    private func syncM3U(playlistUrl: String) async throws -> Set<String> {
        await MainActor.run { self.syncStatusMessage = "Downloading M3U..." }
        guard let url = URL(string: playlistUrl) else { throw URLError(.badURL) }
        let (data, response) = try await UnsafeSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        
        if let content = String(data: data, encoding: .utf8) {
            await MainActor.run { self.syncStatusMessage = "Parsing..." }
            let channels = await M3UParser.parse(content: content, playlistUrl: playlistUrl)
            await saveBatch(items: channels) // M3U doesn't support smart partial updates easily
            return Set(channels.map { $0.url })
        }
        return []
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
        
        // Notify UI less aggressively (only after batch)
        await MainActor.run { self.objectWillChange.send() }
    }
    
    private func deleteOrphans(urls: [String], playlistUrl: String) async {
        guard !urls.isEmpty else { return }
        
        let chunkSize = 500
        let chunks = stride(from: 0, to: urls.count, by: chunkSize).map {
            Array(urls[$0..<min($0 + chunkSize, urls.count)])
        }
        
        await container.performBackgroundTask { context in
            for chunk in chunks {
                let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
                fetch.predicate = NSPredicate(format: "playlistUrl == %@ AND url IN %@", playlistUrl, chunk)
                let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
                _ = try? context.execute(deleteReq)
            }
            try? context.save()
        }
    }
}
