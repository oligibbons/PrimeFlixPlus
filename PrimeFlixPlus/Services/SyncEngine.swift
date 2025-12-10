import Foundation
import CoreData

/// Worker class responsible for synchronizing remote playlists with the local database.
/// Handles Parsing, Diffing, and Batch Persistence.
class SyncEngine {
    
    private let container: NSPersistentContainer
    private let xtreamClient: XtreamClient
    
    init(container: NSPersistentContainer, xtreamClient: XtreamClient) {
        self.container = container
        self.xtreamClient = xtreamClient
    }
    
    // MARK: - Main Sync Loop
    
    /// Performs a full sync for a specific playlist.
    func sync(
        playlist: Playlist,
        force: Bool,
        onStatus: @escaping (String) -> Void,
        onStats: @escaping (SyncStats) -> Void
    ) async throws -> Bool {
        
        guard let source = DataSourceType(rawValue: playlist.source) else { return false }
        
        // 1. Cache Check
        if !force && isCacheFresh(for: playlist.url) {
            print("✅ [SyncEngine] Skipping \(playlist.title) - Cache is fresh.")
            return false
        }
        
        // Use a background context for all heavy lifting
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // 2. Fetch Existing State (Snapshots for Diffing)
        onStatus("Analyzing library...")
        let existingSnapshots = try fetchSnapshots(context: context, playlistUrl: playlist.url)
        
        // 3. Download & Parse
        onStatus("Downloading content...")
        var incomingStructs: [ChannelStruct] = []
        var stats = SyncStats()
        
        if source == .xtream {
            let input = XtreamInput.decodeFromPlaylistUrl(playlist.url)
            
            // Parallel Fetch
            onStatus("Fetching Xtream data...")
            
            // We use a task group to fetch all required endpoints in parallel
            try await withThrowingTaskGroup(of: Void.self) { group in
                var liveItems: [XtreamChannelInfo.LiveStream] = []
                var vodItems: [XtreamChannelInfo.VodStream] = []
                var seriesItems: [XtreamChannelInfo.Series] = []
                var catMap: [String: String] = [:]
                
                // Fetch Live
                async let live = xtreamClient.getLiveStreams(input: input)
                // Fetch VOD
                async let vod = xtreamClient.getVodStreams(input: input)
                // Fetch Series
                async let series = xtreamClient.getSeries(input: input)
                // Fetch Categories
                async let categories = fetchCategories(input: input)
                
                // Await all results
                let (fetchedLive, fetchedVod, fetchedSeries, fetchedCats) = try await (live, vod, series, categories)
                
                liveItems = fetchedLive
                vodItems = fetchedVod
                seriesItems = fetchedSeries
                catMap = fetchedCats
                
                onStatus("Processing \(liveItems.count + vodItems.count) items...")
                
                // Map to unified struct
                let allLive = liveItems.map { ChannelStruct.from($0, playlistUrl: playlist.url, input: input, categoryMap: catMap) }
                let allVod = vodItems.map { ChannelStruct.from($0, playlistUrl: playlist.url, input: input, categoryMap: catMap) }
                let allSeries = seriesItems.map { ChannelStruct.from($0, playlistUrl: playlist.url, categoryMap: catMap) }
                
                incomingStructs = allLive + allVod + allSeries
                
                stats.liveChannelsAdded = allLive.count
                stats.moviesAdded = allVod.count
                stats.seriesAdded = allSeries.count
                stats.totalProcessed = incomingStructs.count
            }
            onStats(stats)
            
        } else if source == .m3u {
            onStatus("Downloading Playlist...")
            guard let url = URL(string: playlist.url) else { throw URLError(.badURL) }
            let (data, _) = try await UnsafeSession.shared.data(from: url)
            
            onStatus("Parsing M3U...")
            if let content = String(data: data, encoding: .utf8) {
                incomingStructs = await M3UParser.parse(content: content, playlistUrl: playlist.url)
                stats.totalProcessed = incomingStructs.count
                onStats(stats)
            }
        }
        
        // 4. Diffing Logic
        onStatus("Saving changes...")
        var toInsert: [ChannelStruct] = []
        var toUpdate: [ChannelStruct] = []
        var processedUrls = Set<String>()
        
        for item in incomingStructs {
            processedUrls.insert(item.url)
            
            if let existing = existingSnapshots[item.url] {
                // Check Content Hash to see if metadata changed
                if existing.contentHash != item.contentHash {
                    toUpdate.append(item)
                }
            } else {
                toInsert.append(item)
            }
        }
        
        // 5. Batch Operations
        if !toInsert.isEmpty {
            onStatus("Adding \(toInsert.count) new items...")
            try await performBatchInsert(items: toInsert, context: context)
        }
        
        if !toUpdate.isEmpty {
            onStatus("Updating \(toUpdate.count) items...")
            try await performBatchUpdate(items: toUpdate, existingSnapshots: existingSnapshots, context: context)
        }
        
        // Calculate Orphans (Items in DB but not in incoming list)
        let existingUrls = Set(existingSnapshots.keys)
        let orphans = existingUrls.subtracting(processedUrls)
        
        if !orphans.isEmpty {
            onStatus("Cleaning \(orphans.count) old items...")
            try await performBatchDelete(urls: Array(orphans), playlistUrl: playlist.url, context: context)
        }
        
        markCacheAsFresh(for: playlist.url)
        
        // Return true if we made any changes
        return !toInsert.isEmpty || !toUpdate.isEmpty || !orphans.isEmpty
    }
    
    // MARK: - Internal Logic
    
    private struct ChannelSnapshot {
        let objectID: NSManagedObjectID
        let contentHash: Int
    }
    
    private func fetchSnapshots(context: NSManagedObjectContext, playlistUrl: String) throws -> [String: ChannelSnapshot] {
        var snapshots: [String: ChannelSnapshot] = [:]
        var fetchError: Error?
        
        // Safe synchronous execution on the background context
        context.performAndWait {
            let req = NSFetchRequest<NSDictionary>(entityName: "Channel")
            req.resultType = .dictionaryResultType
            req.predicate = NSPredicate(format: "playlistUrl == %@", playlistUrl)
            req.propertiesToFetch = ["url", "title", "group", "objectID", "seriesId", "season", "episode"]
            
            do {
                let results = try context.fetch(req)
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
                        hasher.combine(sid)
                        hasher.combine(s)
                        hasher.combine(e)
                        
                        snapshots[url] = ChannelSnapshot(objectID: oid, contentHash: hasher.finalize())
                    }
                }
            } catch {
                fetchError = error
            }
        }
        
        if let error = fetchError { throw error }
        return snapshots
    }
    
    private func fetchCategories(input: XtreamInput) async -> [String: String] {
        // Parallel fetch for Live and VOD categories using TaskGroup
        return await withTaskGroup(of: [String: String].self) { group in
            group.addTask {
                var map: [String: String] = [:]
                if let liveCats = try? await self.xtreamClient.getLiveCategories(input: input) {
                    for c in liveCats { map[c.categoryId] = c.categoryName }
                }
                return map
            }
            group.addTask {
                var map: [String: String] = [:]
                if let vodCats = try? await self.xtreamClient.getVodCategories(input: input) {
                    for c in vodCats { map[c.categoryId] = c.categoryName }
                }
                return map
            }
            
            var combined: [String: String] = [:]
            for await result in group {
                combined.merge(result) { (current, _) in current }
            }
            return combined
        }
    }
    
    // MARK: - Batch Operations
    
    private func performBatchInsert(items: [ChannelStruct], context: NSManagedObjectContext) async throws {
        let batchSize = 5000
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
    }
    
    private func performBatchUpdate(items: [ChannelStruct], existingSnapshots: [String: ChannelSnapshot], context: NSManagedObjectContext) async throws {
        // Core Data batch updates are tricky with complex logic, so we use object-level updates in blocks
        // For performance, we still group them
        await context.perform {
            for item in items {
                guard let snapshot = existingSnapshots[item.url],
                      let obj = context.object(with: snapshot.objectID) as? Channel else { continue }
                
                obj.title = item.title
                obj.group = item.group
                obj.cover = item.cover
                if obj.canonicalTitle == nil { obj.canonicalTitle = item.canonicalTitle }
                if obj.quality == nil { obj.quality = item.quality }
                obj.seriesId = item.seriesId
                obj.season = Int16(item.season)
                obj.episode = Int16(item.episode)
                
                // Correction for misidentified types
                if obj.type != item.type { obj.type = item.type }
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
    }
    
    // MARK: - Helpers
    
    private func isCacheFresh(for url: String) -> Bool {
        let key = "last_sync_\(url)"
        let lastSync = UserDefaults.standard.double(forKey: key)
        if lastSync == 0 { return false }
        return Date().timeIntervalSince(Date(timeIntervalSince1970: lastSync)) < (12 * 60 * 60) // 12 Hours
    }
    
    private func markCacheAsFresh(for url: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_sync_\(url)")
    }
}
