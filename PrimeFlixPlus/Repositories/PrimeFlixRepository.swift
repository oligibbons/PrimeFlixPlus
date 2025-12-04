import Foundation
import CoreData
import Combine
import SwiftUI

// Lightweight struct for diffing
fileprivate struct ChannelSnapshot {
    let objectID: NSManagedObjectID
    let contentHash: Int
}

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
    
    // Main Context Accessor
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
        // Optimized delete using Batch Request
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
        fetch.predicate = NSPredicate(format: "playlistUrl == %@", plUrl)
        let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
        _ = try? context.execute(deleteReq)
        context.delete(playlist)
        try? context.save()
        self.objectWillChange.send()
    }
    
    // MARK: - Smart Accessors (Passthroughs)
    func getSmartContinueWatching(type: String) -> [Channel] { return channelRepo.getSmartContinueWatching(type: type) }
    func getFavorites(type: String) -> [Channel] { return channelRepo.getFavorites(type: type) }
    func getRecentlyAdded(type: String, limit: Int) -> [Channel] { return channelRepo.getRecentlyAdded(type: type, limit: limit) }
    func getRecentFallback(type: String, limit: Int) -> [Channel] { return channelRepo.getRecentFallback(type: type, limit: limit) }
    func getByGenre(type: String, groupName: String, limit: Int) -> [Channel] { return channelRepo.getByGenre(type: type, groupName: groupName, limit: limit) }
    func getRecommended(type: String) -> [Channel] { return channelRepo.getRecommended(type: type) }
    func getVersions(for channel: Channel) -> [Channel] { return channelRepo.getVersions(for: channel) }
    func getGroups(playlistUrl: String, type: StreamType) -> [String] { return channelRepo.getGroups(playlistUrl: playlistUrl, type: type.rawValue) }
    func getBrowsingContent(playlistUrl: String, type: String, group: String) -> [Channel] { return channelRepo.getBrowsingContent(playlistUrl: playlistUrl, type: type, group: group) }
    func getTrendingMatches(type: String, tmdbResults: [String]) -> [Channel] { return channelRepo.getTrendingMatches(type: type, tmdbResults: tmdbResults) }
    
    func toggleFavorite(_ channel: Channel) {
        channelRepo.toggleFavorite(channel: channel)
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
    
    nonisolated func getTrendingMatchesAsync(type: String, tmdbResults: [String]) async -> [NSManagedObjectID] {
        let bgContext = container.newBackgroundContext()
        return await bgContext.perform {
            var matches: [NSManagedObjectID] = []
            var seenTitles = Set<String>()
            for title in tmdbResults {
                let req = NSFetchRequest<Channel>(entityName: "Channel")
                req.predicate = NSPredicate(format: "type == %@ AND title CONTAINS[cd] %@", type, title)
                req.fetchLimit = 1
                if let match = try? bgContext.fetch(req).first {
                    let rawForDedup = match.canonicalTitle ?? match.title
                    let norm = TitleNormalizer.parse(rawTitle: rawForDedup).normalizedTitle
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
    
    nonisolated func syncPlaylist(playlistTitle: String, playlistUrl: String, source: DataSourceType, isAutoSync: Bool = false) async {
        await MainActor.run {
            if !isAutoSync { self.isSyncing = true; self.isErrorState = false }
            self.syncStatusMessage = "Checking Library..."
        }
        
        // 1. FAST Snapshot: Fetch [URL: Hash] only.
        var existingSnapshots: [String: ChannelSnapshot] = [:]
        let context = container.newBackgroundContext()
        
        await context.perform {
            let req = NSFetchRequest<NSDictionary>(entityName: "Channel")
            req.resultType = .dictionaryResultType
            req.predicate = NSPredicate(format: "playlistUrl == %@", playlistUrl)
            req.propertiesToFetch = ["url", "title", "group"]
            
            if let results = try? context.fetch(req) {
                for dict in results {
                    if let url = dict["url"] as? String,
                       let title = dict["title"] as? String,
                       let group = dict["group"] as? String,
                       let oid = dict["objectID"] as? NSManagedObjectID {
                        
                        var hasher = Hasher()
                        hasher.combine(title)
                        hasher.combine(group)
                        existingSnapshots[url] = ChannelSnapshot(objectID: oid, contentHash: hasher.finalize())
                    }
                }
            }
        }
        
        var processedUrls = Set<String>()
        
        do {
            var incomingStructs: [ChannelStruct] = []
            
            // 2. Network Fetch & Parse
            if source == .xtream {
                let input = XtreamInput.decodeFromPlaylistUrl(playlistUrl)
                let catMap = try await fetchXtreamCategoriesWithTimeout(input: input, timeoutSeconds: 30)
                
                await MainActor.run { self.syncStatusMessage = "Updating Content..." }
                
                async let live = xtreamClient.getLiveStreams(input: input)
                async let vod = xtreamClient.getVodStreams(input: input)
                async let series = xtreamClient.getSeries(input: input)
                
                let (liveItems, vodItems, seriesItems) = try await (live, vod, series)
                
                incomingStructs.append(contentsOf: liveItems.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input, categoryMap: catMap) })
                incomingStructs.append(contentsOf: vodItems.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input, categoryMap: catMap) })
                incomingStructs.append(contentsOf: seriesItems.map { ChannelStruct.from($0, playlistUrl: playlistUrl, categoryMap: catMap) })
                
            } else if source == .m3u {
                guard let url = URL(string: playlistUrl) else { throw URLError(.badURL) }
                let (data, _) = try await UnsafeSession.shared.data(from: url)
                if let content = String(data: data, encoding: .utf8) {
                    incomingStructs = await M3UParser.parse(content: content, playlistUrl: playlistUrl)
                }
            }
            
            // 3. Diffing
            var toInsert: [ChannelStruct] = []
            var toUpdate: [ChannelStruct] = []
            
            for item in incomingStructs {
                processedUrls.insert(item.url)
                
                if let existing = existingSnapshots[item.url] {
                    if existing.contentHash != item.contentHash {
                        toUpdate.append(item)
                    }
                } else {
                    toInsert.append(item)
                }
            }
            
            // 4. Batch Execution
            // CRITICAL FIX: Shadow variables with 'let' to satisfy Concurrency Checker
            if !toInsert.isEmpty {
                let finalInserts = toInsert
                await MainActor.run { self.syncStatusMessage = "Adding \(finalInserts.count) new items..." }
                try await performBatchInsert(items: finalInserts, context: context)
            }
            
            if !toUpdate.isEmpty {
                let finalUpdates = toUpdate
                await MainActor.run { self.syncStatusMessage = "Updating \(finalUpdates.count) items..." }
                try await performBatchUpdate(items: finalUpdates, existingSnapshots: existingSnapshots, context: context)
            }
            
            // 5. Orphan Deletion
            let existingUrls = Set(existingSnapshots.keys)
            let orphans = existingUrls.subtracting(processedUrls)
            
            if !orphans.isEmpty {
                await MainActor.run { self.syncStatusMessage = "Cleaning up..." }
                try await performBatchDelete(urls: Array(orphans), playlistUrl: playlistUrl, context: context)
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
                    try? await Task.sleep(nanoseconds: 4 * 1_000_000_000)
                    self.syncStatusMessage = nil
                    self.isErrorState = false
                }
            }
        }
    }
    
    // MARK: - High Performance Batch Operations
    
    private func performBatchInsert(items: [ChannelStruct], context: NSManagedObjectContext) async throws {
        let batchSize = 2000
        let chunks = stride(from: 0, to: items.count, by: batchSize).map {
            Array(items[$0..<min($0 + batchSize, items.count)])
        }
        
        await context.perform {
            for chunk in chunks {
                let objects = chunk.map { $0.toDictionary() }
                let batchInsert = NSBatchInsertRequest(entity: Channel.entity(), objects: objects)
                batchInsert.resultType = .statusOnly
                _ = try? context.execute(batchInsert)
            }
        }
        await MainActor.run { self.objectWillChange.send() }
    }
    
    private func performBatchUpdate(items: [ChannelStruct], existingSnapshots: [String: ChannelSnapshot], context: NSManagedObjectContext) async throws {
        await context.perform {
            for item in items {
                guard let snapshot = existingSnapshots[item.url] else { continue }
                if let obj = try? context.existingObject(with: snapshot.objectID) as? Channel {
                    obj.title = item.title
                    obj.group = item.group
                    obj.cover = item.cover
                    if obj.canonicalTitle == nil { obj.canonicalTitle = item.canonicalTitle }
                    if obj.quality == nil { obj.quality = item.quality }
                }
            }
            try? context.save()
        }
    }
    
    private func performBatchDelete(urls: [String], playlistUrl: String, context: NSManagedObjectContext) async throws {
        let batchSize = 1000
        let chunks = stride(from: 0, to: urls.count, by: batchSize).map {
            Array(urls[$0..<min($0 + batchSize, urls.count)])
        }
        
        await context.perform {
            for chunk in chunks {
                let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
                fetch.predicate = NSPredicate(format: "playlistUrl == %@ AND url IN %@", playlistUrl, chunk)
                let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
                _ = try? context.execute(deleteReq)
            }
            context.reset()
        }
        await MainActor.run { self.objectWillChange.send() }
    }
    
    private func fetchXtreamCategoriesWithTimeout(input: XtreamInput, timeoutSeconds: Int) async throws -> [String: String] {
        await MainActor.run { self.syncStatusMessage = "Fetching Categories..." }
        
        return await withTaskGroup(of: [String: String]?.self) { group in
            group.addTask {
                var map: [String: String] = [:]
                if let liveCats = try? await self.xtreamClient.getLiveCategories(input: input) {
                    for c in liveCats { map[c.categoryId] = c.categoryName }
                }
                if let vodCats = try? await self.xtreamClient.getVodCategories(input: input) {
                    for c in vodCats { map[c.categoryId] = c.categoryName }
                }
                return map
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                return nil
            }
            if let firstResult = await group.next() {
                group.cancelAll()
                return firstResult ?? [:]
            }
            return [:]
        }
    }
}
