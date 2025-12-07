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

// Lightweight struct for diffing
fileprivate struct ChannelSnapshot {
    let objectID: NSManagedObjectID
    let contentHash: Int
}

@MainActor
class PrimeFlixRepository: ObservableObject {
    
    // --- State ---
    @Published var isSyncing: Bool = false
    @Published var isInitialSync: Bool = false
    @Published var syncStatusMessage: String? = nil
    @Published var lastSyncDate: Date? = nil
    @Published var isErrorState: Bool = false
    
    // Real-time Feedback for Loading Screen
    @Published var syncStats: SyncStats = SyncStats()
    
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
                await self.syncPlaylist(playlistTitle: title, playlistUrl: url, source: source, force: true, isFirstTime: true)
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
    
    func searchLiveContent(query: String) -> (categories: [String], channels: [Channel]) {
        return channelRepo.searchLiveContent(query: query)
    }
    
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
                await self.syncPlaylist(playlistTitle: playlist.title, playlistUrl: playlist.url, source: source, force: force, isFirstTime: false)
            }
            
            await MainActor.run {
                if !self.isErrorState {
                    if force || self.syncStatusMessage != nil {
                        self.syncStatusMessage = "Sync Complete"
                    }
                    self.lastSyncDate = Date()
                    self.isInitialSync = false
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
    
    nonisolated func syncPlaylist(playlistTitle: String, playlistUrl: String, source: DataSourceType, force: Bool, isFirstTime: Bool) async {
        
        if !force && isCacheFresh(for: playlistUrl) {
            print("✅ [Sync] Skipping \(playlistTitle) - Cache is fresh (< 12 hours).")
            return
        }
        
        await MainActor.run {
            self.syncStatusMessage = isFirstTime ? "Setting up \(playlistTitle)..." : "Checking for updates..."
            self.isSyncing = true
            self.isInitialSync = isFirstTime
            self.syncStats.currentStage = "Connecting to server..."
        }
        
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        await MainActor.run { self.syncStats.currentStage = "Analyzing local library..." }
        
        var existingSnapshots: [String: ChannelSnapshot] = [:]
        
        await context.perform {
            let req = NSFetchRequest<NSDictionary>(entityName: "Channel")
            req.resultType = .dictionaryResultType
            req.predicate = NSPredicate(format: "playlistUrl == %@", playlistUrl)
            req.propertiesToFetch = ["url", "title", "group", "objectID", "seriesId", "season", "episode"]
            
            if let results = try? context.fetch(req) {
                for dict in results {
                    if let url = dict["url"] as? String,
                       let title = dict["title"] as? String,
                       let group = dict["group"] as? String,
                       let oid = dict["objectID"] as? NSManagedObjectID {
                        
                        let sid = dict["seriesId"] as? String
                        let s = dict["season"] as? Int ?? 0
                        let e = dict["episode"] as? Int ?? 0
                        
                        var hasher = Hasher()
                        hasher.combine(title)
                        hasher.combine(group)
                        // Include metadata in hash so S/E corrections trigger an update
                        hasher.combine(sid)
                        hasher.combine(s)
                        hasher.combine(e)
                        
                        existingSnapshots[url] = ChannelSnapshot(objectID: oid, contentHash: hasher.finalize())
                    }
                }
            }
        }
        
        var processedUrls = Set<String>()
        
        do {
            var incomingStructs: [ChannelStruct] = []
            
            await MainActor.run { self.syncStats.currentStage = "Downloading playlists..." }
            
            if source == .xtream {
                let input = XtreamInput.decodeFromPlaylistUrl(playlistUrl)
                let catMap = try await fetchXtreamCategoriesWithTimeout(input: input, timeoutSeconds: 30)
                
                async let live = xtreamClient.getLiveStreams(input: input)
                async let vod = xtreamClient.getVodStreams(input: input)
                async let series = xtreamClient.getSeries(input: input)
                
                let (liveItems, vodItems, seriesItems) = try await (live, vod, series)
                
                await MainActor.run { self.syncStats.currentStage = "Processing content..." }
                
                // These factory methods now populate season/episode/seriesId
                let allLive = liveItems.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input, categoryMap: catMap) }
                let allVod = vodItems.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input, categoryMap: catMap) }
                let allSeries = seriesItems.map { ChannelStruct.from($0, playlistUrl: playlistUrl, categoryMap: catMap) }
                
                incomingStructs.append(contentsOf: allLive)
                incomingStructs.append(contentsOf: allVod)
                incomingStructs.append(contentsOf: allSeries)
                
                await MainActor.run {
                    self.syncStats.liveChannelsAdded = allLive.count
                    self.syncStats.moviesAdded = allVod.count
                    self.syncStats.seriesAdded = allSeries.count
                }
                
            } else if source == .m3u {
                guard let url = URL(string: playlistUrl) else { throw URLError(.badURL) }
                let (data, _) = try await UnsafeSession.shared.data(from: url)
                if let content = String(data: data, encoding: .utf8) {
                    incomingStructs = await M3UParser.parse(content: content, playlistUrl: playlistUrl)
                    
                    let count = incomingStructs.count
                    await MainActor.run {
                        self.syncStats.totalProcessed = count
                        self.syncStats.currentStage = "Sorting channels..."
                    }
                }
            }
            
            // Diffing Logic
            var toInsert: [ChannelStruct] = []
            var toUpdate: [ChannelStruct] = []
            
            await MainActor.run { self.syncStats.currentStage = "Saving changes..." }
            
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
            
            let existingUrls = Set(existingSnapshots.keys)
            let orphans = existingUrls.subtracting(processedUrls)
            
            if !orphans.isEmpty {
                await MainActor.run { self.syncStatusMessage = "Cleaning up \(orphans.count) old items..." }
                try await performBatchDelete(urls: Array(orphans), playlistUrl: playlistUrl, context: context)
            }
            
            // MARK: - Movie Poster Enrichment Step (NEW)
            // Only run if we actually added/updated movies or if it's the very first sync
            if isFirstTime || !toInsert.isEmpty {
                await enrichMovies(context: context, playlistUrl: playlistUrl)
            }
            
            markCacheAsFresh(for: playlistUrl)
            
        } catch {
            print("❌ Sync Failed: \(error)")
            await MainActor.run {
                self.isErrorState = true
                self.syncStatusMessage = "Sync Failed"
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
            deleteReq.resultType = .resultTypeObjectIDs
            
            _ = try? bgContext.execute(deleteReq)
            try? bgContext.save()
            bgContext.reset()
        }
        
        UserDefaults.standard.removeObject(forKey: "last_sync_\(playlist.url)")
        
        await Task.detached {
            await self.syncPlaylist(playlistTitle: playlist.title, playlistUrl: playlist.url, source: source, force: true, isFirstTime: true)
            
            await MainActor.run {
                self.syncStatusMessage = "Library Rebuilt"
                Task {
                    try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                    self.syncStatusMessage = nil
                    self.isSyncing = false
                    self.isInitialSync = false
                }
            }
        }.value
    }
    
    // MARK: - Enrichment Logic (NEW)
    
    private nonisolated func enrichMovies(context: NSManagedObjectContext, playlistUrl: String) async {
        await MainActor.run {
            self.syncStatusMessage = "Enriching Movie Posters..."
            self.syncStats.currentStage = "Fetching missing covers..."
        }
        
        // 1. Identify candidates (Movies with missing/generic covers)
        var fetchedCandidates: [NSManagedObjectID] = []
        
        await context.perform {
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            // Target movies from this playlist
            // Check for nil cover OR empty string OR if it looks like a generic icon
            req.predicate = NSPredicate(format: "playlistUrl == %@ AND type == 'movie'", playlistUrl)
            // Limit to reasonable batch to avoid timeout
            req.fetchLimit = 2000
            
            if let results = try? context.fetch(req) {
                // Heuristic: If cover is nil, empty, or just a generic Xtream icon ID
                fetchedCandidates = results.filter { ch in
                    guard let c = ch.cover, !c.isEmpty else { return true }
                    return false
                }.map { $0.objectID }
            }
        }
        
        // FIX: Freeze mutable array to immutable constant for safe concurrent access
        let candidates = fetchedCandidates
        
        if candidates.isEmpty { return }
        
        // 2. Process in batches to respect API limits
        let batchSize = 10
        let chunks = stride(from: 0, to: candidates.count, by: batchSize).map {
            Array(candidates[$0..<min($0 + batchSize, candidates.count)])
        }
        
        for (index, chunk) in chunks.enumerated() {
            // Update UI occasionally
            if index % 5 == 0 {
                let progressMsg = "Enriching Movies (\(index * batchSize)/\(candidates.count))..."
                await MainActor.run {
                    self.syncStatusMessage = progressMsg
                }
            }
            
            await withTaskGroup(of: (NSManagedObjectID, String?).self) { group in
                for oid in chunk {
                    group.addTask {
                        var rawTitle: String = ""
                        
                        // Perform on context just to get strings, then release lock
                        await context.perform {
                            if let ch = try? context.existingObject(with: oid) as? Channel {
                                rawTitle = ch.canonicalTitle ?? ch.title
                            }
                        }
                        
                        if rawTitle.isEmpty { return (oid, nil) }
                        
                        // Parse & Search
                        let info = TitleNormalizer.parse(rawTitle: rawTitle)
                        if let results = try? await self.tmdbClient.searchMovie(query: info.normalizedTitle, year: info.year) {
                            if let best = results.first, let path = best.posterPath {
                                return (oid, "https://image.tmdb.org/t/p/w500\(path)")
                            }
                        }
                        return (oid, nil)
                    }
                }
                
                // Collect results and save
                var updates: [(NSManagedObjectID, String)] = []
                for await (oid, newCover) in group {
                    if let cover = newCover {
                        updates.append((oid, cover))
                    }
                }
                
                if !updates.isEmpty {
                    await context.perform {
                        for (oid, cover) in updates {
                            if let ch = try? context.existingObject(with: oid) as? Channel {
                                ch.cover = cover
                            }
                        }
                        try? context.save()
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private nonisolated func isCacheFresh(for url: String) -> Bool {
        let key = "last_sync_\(url)"
        let lastSync = UserDefaults.standard.double(forKey: key)
        if lastSync == 0 { return false }
        let date = Date(timeIntervalSince1970: lastSync)
        return Date().timeIntervalSince(date) < (12 * 60 * 60)
    }
    
    private nonisolated func markCacheAsFresh(for url: String) {
        let key = "last_sync_\(url)"
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }
    
    private func performBatchInsert(items: [ChannelStruct], context: NSManagedObjectContext) async throws {
        let batchSize = 5000
        let chunks = stride(from: 0, to: items.count, by: batchSize).map {
            Array(items[$0..<min($0 + batchSize, items.count)])
        }
        await context.perform {
            for chunk in chunks {
                // Dictionary creation handles all fields, including new Metadata
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
                let obj = context.object(with: snapshot.objectID) as? Channel
                
                // Update standard fields
                obj?.title = item.title
                obj?.group = item.group
                obj?.cover = item.cover
                if obj?.canonicalTitle == nil { obj?.canonicalTitle = item.canonicalTitle }
                if obj?.quality == nil { obj?.quality = item.quality }
                
                // Update Metadata
                obj?.seriesId = item.seriesId
                obj?.season = Int16(item.season)
                obj?.episode = Int16(item.episode)
                
                // If type changed (e.g. from movie to series_episode), update it
                if obj?.type != item.type { obj?.type = item.type }
            }
            try? context.save()
        }
    }

    private func performBatchDelete(urls: [String], playlistUrl: String, context: NSManagedObjectContext) async throws {
        let batchSize = 2000
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
