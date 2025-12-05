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
                // New playlist: Force immediate sync
                await self.syncPlaylist(playlistTitle: title, playlistUrl: url, source: source, force: true)
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
    
    /// Global sync called on app launch. Respects cache timers.
    func syncAll(force: Bool = false) async {
        guard !isSyncing else { return }
        let playlists = getAllPlaylists()
        guard !playlists.isEmpty else { return }
        
        self.isSyncing = true
        self.isErrorState = false
        
        await Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            for playlist in playlists {
                guard let source = DataSourceType(rawValue: playlist.source) else { continue }
                // On launch (syncAll), we default to force=false so we can skip recent updates
                await self.syncPlaylist(playlistTitle: playlist.title, playlistUrl: playlist.url, source: source, force: force)
            }
            
            await MainActor.run {
                if !self.isErrorState {
                    // Only show "Done" if we actually did something visible, otherwise just go silent
                    if force || self.syncStatusMessage != nil {
                        self.syncStatusMessage = "Sync Complete"
                    }
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
    
    /// The Core Sync Engine
    /// - Parameters:
    ///   - force: If true, ignores the time check and forces a network fetch.
    nonisolated func syncPlaylist(playlistTitle: String, playlistUrl: String, source: DataSourceType, force: Bool) async {
        // 1. Smart Cache Check
        // isCacheFresh is now nonisolated, so we can call it synchronously here
        if !force && isCacheFresh(for: playlistUrl) {
            print("✅ [Sync] Skipping \(playlistTitle) - Cache is fresh (< 12 hours).")
            return
        }
        
        await MainActor.run {
            self.syncStatusMessage = "Updating \(playlistTitle)..."
            self.isSyncing = true // Ensure UI shows loading if we passed the check
        }
        
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // 2. Snapshot Existing Data (Fast)
        var existingSnapshots: [String: ChannelSnapshot] = [:]
        
        await context.perform {
            let req = NSFetchRequest<NSDictionary>(entityName: "Channel")
            req.resultType = .dictionaryResultType
            req.predicate = NSPredicate(format: "playlistUrl == %@", playlistUrl)
            req.propertiesToFetch = ["url", "title", "group", "objectID"]
            
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
            
            // 3. Network Fetch & Parse
            if source == .xtream {
                let input = XtreamInput.decodeFromPlaylistUrl(playlistUrl)
                let catMap = try await fetchXtreamCategoriesWithTimeout(input: input, timeoutSeconds: 30)
                
                // Fetch in parallel
                async let live = xtreamClient.getLiveStreams(input: input)
                async let vod = xtreamClient.getVodStreams(input: input)
                async let series = xtreamClient.getSeries(input: input)
                
                let (liveItems, vodItems, seriesItems) = try await (live, vod, series)
                
                // Parse
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
            
            // 4. Diffing Logic (The "Check against cache" part)
            var toInsert: [ChannelStruct] = []
            var toUpdate: [ChannelStruct] = []
            
            for item in incomingStructs {
                processedUrls.insert(item.url)
                
                if let existing = existingSnapshots[item.url] {
                    // Only update if content (Title/Group) changed
                    if existing.contentHash != item.contentHash {
                        toUpdate.append(item)
                    }
                } else {
                    // New item
                    toInsert.append(item)
                }
            }
            
            // 5. Batch Execution
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
            
            // 6. Orphan Deletion (Remove items not in the new list)
            let existingUrls = Set(existingSnapshots.keys)
            let orphans = existingUrls.subtracting(processedUrls)
            
            if !orphans.isEmpty {
                await MainActor.run { self.syncStatusMessage = "Cleaning up..." }
                try await performBatchDelete(urls: Array(orphans), playlistUrl: playlistUrl, context: context)
            }
            
            // 7. Mark as Fresh
            markCacheAsFresh(for: playlistUrl)
            
        } catch {
            print("❌ Sync Failed: \(error)")
            await MainActor.run {
                self.isErrorState = true
                self.syncStatusMessage = "Sync Failed"
            }
        }
    }
    
    // MARK: - Nuclear Option
    
    func nuclearResync(playlist: Playlist) async {
        guard let source = DataSourceType(rawValue: playlist.source) else { return }
        
        self.isSyncing = true
        self.syncStatusMessage = "Wiping Database..."
        
        // 1. Wipe Data
        let bgContext = container.newBackgroundContext()
        await bgContext.perform {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
            fetch.predicate = NSPredicate(format: "playlistUrl == %@", playlist.url)
            let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
            deleteReq.resultType = .resultTypeObjectIDs // Optional: Return IDs to merge changes
            
            // Execute Delete
            try? bgContext.execute(deleteReq)
            try? bgContext.save()
            bgContext.reset()
        }
        
        // 2. Clear Timestamp
        UserDefaults.standard.removeObject(forKey: "last_sync_\(playlist.url)")
        
        // 3. Force Sync
        // We use Task.detached to break out of any UI blocking, effectively restarting the process
        await Task.detached {
            await self.syncPlaylist(playlistTitle: playlist.title, playlistUrl: playlist.url, source: source, force: true)
            
            await MainActor.run {
                self.syncStatusMessage = "Library Rebuilt"
                Task {
                    try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                    self.syncStatusMessage = nil
                    self.isSyncing = false
                }
            }
        }.value
    }
    
    // MARK: - Helpers & Batch Ops
    
    // Marked as nonisolated to allow calling from background/nonisolated contexts without await
    private nonisolated func isCacheFresh(for url: String) -> Bool {
        let key = "last_sync_\(url)"
        let lastSync = UserDefaults.standard.double(forKey: key)
        if lastSync == 0 { return false } // Never synced
        
        let date = Date(timeIntervalSince1970: lastSync)
        // 12 Hour Threshold
        return Date().timeIntervalSince(date) < (12 * 60 * 60)
    }
    
    // Marked as nonisolated for the same reason
    private nonisolated func markCacheAsFresh(for url: String) {
        let key = "last_sync_\(url)"
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }
    
    private func performBatchInsert(items: [ChannelStruct], context: NSManagedObjectContext) async throws {
        let batchSize = 5000 // Increased batch size for speed
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
                // Note: Batch Update Request is tricky with varied data.
                // Standard fetch-update-save is safer for updates unless mass-updating a single property.
                // We optimize by only updating the object we already have an ID for.
                let obj = context.object(with: snapshot.objectID) as? Channel
                obj?.title = item.title
                obj?.group = item.group
                obj?.cover = item.cover
                if obj?.canonicalTitle == nil { obj?.canonicalTitle = item.canonicalTitle }
                if obj?.quality == nil { obj?.quality = item.quality }
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
