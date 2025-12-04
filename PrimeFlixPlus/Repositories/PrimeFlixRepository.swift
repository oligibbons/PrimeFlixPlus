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
    
    func getTrendingMatches(type: String, tmdbResults: [String]) -> [Channel] {
        return channelRepo.getTrendingMatches(type: type, tmdbResults: tmdbResults)
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
    
    // MARK: - Thread-Safe / Background Accessors (Optimized)
    
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
        
        // 1. Snapshot existing content to avoid duplicates AND allow updates
        var existingMap: [String: NSManagedObjectID] = [:]
        
        let context = container.newBackgroundContext()
        context.performAndWait {
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            req.predicate = NSPredicate(format: "playlistUrl == %@", playlistUrl)
            // Just need URL and ObjectID to map
            req.propertiesToFetch = ["url"]
            
            if let results = try? context.fetch(req) {
                for ch in results {
                    existingMap[ch.url] = ch.objectID
                }
            }
        }
        
        var processedUrls = Set<String>()
        
        do {
            if source == .xtream {
                let input = XtreamInput.decodeFromPlaylistUrl(playlistUrl)
                
                do {
                    let newUrls = try await syncXtreamBulk(input: input, playlistUrl: playlistUrl, existingMap: existingMap)
                    processedUrls.formUnion(newUrls)
                } catch {
                    if let xErr = error as? XtreamError, case .invalidResponse(let code, _) = xErr, [512, 513, 504].contains(code) {
                        await MainActor.run { self.syncStatusMessage = "Deep Sync (Safe Mode)..." }
                        let newUrls = try await syncXtreamByCategories(input: input, playlistUrl: playlistUrl, existingMap: existingMap)
                        processedUrls.formUnion(newUrls)
                    } else {
                        throw error
                    }
                }
                
            } else if source == .m3u {
                let newUrls = try await syncM3U(playlistUrl: playlistUrl, existingMap: existingMap)
                processedUrls.formUnion(newUrls)
            }
            
            // 2. Orphan Deletion
            let existingUrls = Set(existingMap.keys)
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
    
    // MARK: - Sync Helpers (Updated for Upsert)
    
    private func syncXtreamBulk(input: XtreamInput, playlistUrl: String, existingMap: [String: NSManagedObjectID]) async throws -> Set<String> {
        var verified = Set<String>()
        
        await MainActor.run { self.syncStatusMessage = "Checking Live..." }
        let live = try await xtreamClient.getLiveStreams(input: input)
        let liveStructs = live.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
        verified.formUnion(liveStructs.map { $0.url })
        await saveBatch(items: liveStructs, existingMap: existingMap)
        
        await MainActor.run { self.syncStatusMessage = "Checking Movies..." }
        let vod = try await xtreamClient.getVodStreams(input: input)
        let vodStructs = vod.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
        verified.formUnion(vodStructs.map { $0.url })
        await saveBatch(items: vodStructs, existingMap: existingMap)
        
        await MainActor.run { self.syncStatusMessage = "Checking Series..." }
        let series = try await xtreamClient.getSeries(input: input)
        let seriesStructs = series.map { ChannelStruct.from($0, playlistUrl: playlistUrl) }
        verified.formUnion(seriesStructs.map { $0.url })
        await saveBatch(items: seriesStructs, existingMap: existingMap)
        
        return verified
    }
    
    private func syncXtreamByCategories(input: XtreamInput, playlistUrl: String, existingMap: [String: NSManagedObjectID]) async throws -> Set<String> {
        var verified = Set<String>()
        
        let liveCats = try await xtreamClient.getLiveCategories(input: input)
        for (index, cat) in liveCats.enumerated() {
            await MainActor.run { self.syncStatusMessage = "Live: \(cat.categoryName) (\(index + 1)/\(liveCats.count))" }
            if let streams = try? await xtreamClient.getLiveStreams(input: input, categoryId: cat.categoryId) {
                let structs = streams.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
                verified.formUnion(structs.map { $0.url })
                await saveBatch(items: structs, existingMap: existingMap)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        
        let vodCats = try await xtreamClient.getVodCategories(input: input)
        for (index, cat) in vodCats.enumerated() {
            await MainActor.run { self.syncStatusMessage = "Mov: \(cat.categoryName) (\(index + 1)/\(vodCats.count))" }
            if let streams = try? await xtreamClient.getVodStreams(input: input, categoryId: cat.categoryId) {
                let structs = streams.map { ChannelStruct.from($0, playlistUrl: playlistUrl, input: input) }
                verified.formUnion(structs.map { $0.url })
                await saveBatch(items: structs, existingMap: existingMap)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        
        if let series = try? await xtreamClient.getSeries(input: input) {
            let structs = series.map { ChannelStruct.from($0, playlistUrl: playlistUrl) }
            verified.formUnion(structs.map { $0.url })
            await saveBatch(items: structs, existingMap: existingMap)
        }
        
        return verified
    }
    
    private func syncM3U(playlistUrl: String, existingMap: [String: NSManagedObjectID]) async throws -> Set<String> {
        await MainActor.run { self.syncStatusMessage = "Downloading M3U..." }
        guard let url = URL(string: playlistUrl) else { throw URLError(.badURL) }
        let (data, response) = try await UnsafeSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        
        if let content = String(data: data, encoding: .utf8) {
            await MainActor.run { self.syncStatusMessage = "Parsing..." }
            let channels = await M3UParser.parse(content: content, playlistUrl: playlistUrl)
            await saveBatch(items: channels, existingMap: existingMap)
            return Set(channels.map { $0.url })
        }
        return []
    }
    
    private func saveBatch(items: [ChannelStruct], existingMap: [String: NSManagedObjectID]) async {
        guard !items.isEmpty else { return }
        
        await container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            for item in items {
                // UPSERT LOGIC
                if let existingID = existingMap[item.url], let existingChannel = try? context.existingObject(with: existingID) as? Channel {
                    // Update existing
                    existingChannel.title = item.title
                    existingChannel.group = item.group
                    existingChannel.cover = item.cover
                    // Important: Update the canonical title if it was missing
                    if existingChannel.canonicalTitle == nil {
                        existingChannel.canonicalTitle = item.canonicalTitle
                    }
                } else {
                    // Insert new
                    _ = item.toManagedObject(context: context)
                }
            }
            try? context.save()
        }
        
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
