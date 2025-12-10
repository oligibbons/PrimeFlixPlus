import Foundation
import CoreData

/// The primary Data Access Object (DAO) for fetching Channels.
class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Search Result Models
    
    struct LibrarySearchResults {
        let movies: [Channel]
        let series: [Channel]
    }
    
    struct LiveSearchResults {
        let categories: [String]
        let channels: [Channel]
    }
    
    // MARK: - Core Mutators
    
    func toggleFavorite(_ channel: Channel) {
        channel.isFavorite.toggle()
        // Context save is handled by the caller (PrimeFlixRepository)
    }
    
    // MARK: - Core Search Methods
    
    /// Searches Library (Movies & Series).
    func searchLibrary(query: String) -> LibrarySearchResults {
        let rawTerm = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTerm.isEmpty { return LibrarySearchResults(movies: [], series: []) }
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.fetchLimit = 1000
        
        // Search Logic: Title OR File Name (Canonical) OR Group OR Raw URL
        let textMatch = NSPredicate(
            format: "title CONTAINS[cd] %@ OR canonicalTitle CONTAINS[cd] %@ OR group CONTAINS[cd] %@ OR url CONTAINS[cd] %@",
            rawTerm, rawTerm, rawTerm, rawTerm
        )
        let typeMatch = NSPredicate(format: "type IN {'movie', 'series', 'series_episode'}")
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [textMatch, typeMatch])
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        
        var results: [Channel] = []
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        
        // Separation & Deduplication
        let rawMovies = results.filter { $0.type == "movie" }
        // We exclude individual episodes from the main search results if a "Series Container" exists,
        // but since we want to find shows even if only episodes matched, we process them all and group by Show.
        let rawSeries = results.filter { $0.type == "series" || $0.type == "series_episode" }
        
        let uniqueMovies = deduplicate(channels: rawMovies, isSeries: false)
        let uniqueSeries = deduplicate(channels: rawSeries, isSeries: true)
        
        return LibrarySearchResults(movies: uniqueMovies, series: uniqueSeries)
    }
    
    /// Searches Live TV. Returns (Categories, Channels).
    func searchLive(query: String) -> LiveSearchResults {
        let rawTerm = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTerm.isEmpty { return LiveSearchResults(categories: [], channels: []) }
        
        // A. Search Channels
        let channelReq = NSFetchRequest<Channel>(entityName: "Channel")
        channelReq.fetchLimit = 500
        channelReq.predicate = NSPredicate(
            format: "type == 'live' AND (title CONTAINS[cd] %@ OR group CONTAINS[cd] %@ OR url CONTAINS[cd] %@)",
            rawTerm, rawTerm, rawTerm
        )
        channelReq.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        
        var channels: [Channel] = []
        context.performAndWait {
            channels = (try? context.fetch(channelReq)) ?? []
        }
        
        // B. Search Groups (Categories) matching the query
        let groupReq = NSFetchRequest<NSDictionary>(entityName: "Channel")
        groupReq.resultType = .dictionaryResultType
        groupReq.returnsDistinctResults = true
        groupReq.propertiesToFetch = ["group"]
        groupReq.predicate = NSPredicate(format: "type == 'live' AND group CONTAINS[cd] %@", rawTerm)
        groupReq.sortDescriptors = [NSSortDescriptor(key: "group", ascending: true)]
        
        var categories: [String] = []
        context.performAndWait {
            if let dicts = try? context.fetch(groupReq) as? [[String: String]] {
                categories = dicts.compactMap { $0["group"] }
            }
        }
        
        return LiveSearchResults(categories: categories, channels: channels)
    }
    
    // MARK: - Smart Deduplication (The Fix)
    
    /// Groups duplicates but ensures "Unknown Title" items remain unique.
    private func deduplicate(channels: [Channel], isSeries: Bool) -> [Channel] {
        // We use a dictionary to keep the "Best" version of a duplicate set
        var grouped: [String: Channel] = [:]
        var order: [String] = [] // To preserve sort order
        
        for item in channels {
            var key = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            // 1. Handle "Generic/Unknown" Titles (Force Uniqueness)
            if isGenericTitle(item.title) {
                // Use filename/URL as key to prevent collapsing different "Unknown" items
                key = (item.canonicalTitle ?? item.url).lowercased()
            }
            // 2. Handle Series Grouping
            else if isSeries {
                // If it has a SeriesID, use that as the ultimate grouping key
                if let sid = item.seriesId, sid != "0", !sid.isEmpty {
                    key = "sid_\(sid)"
                }
                // If no SeriesID (M3U), we fall back to the Title key above
            }
            
            // 3. Selection Logic ("Keep Best")
            if let existing = grouped[key] {
                // If we already have this item, check if the new one is "better"
                if isBetterVersion(candidate: item, current: existing) {
                    grouped[key] = item
                }
            } else {
                grouped[key] = item
                order.append(key)
            }
        }
        
        // Return items in original sort order
        return order.compactMap { grouped[$0] }
    }
    
    /// Helper to pick the "Best" version to display in the search result
    private func isBetterVersion(candidate: Channel, current: Channel) -> Bool {
        // 1. Prefer items with Cover Art
        let candidateHasCover = (candidate.cover != nil)
        let currentHasCover = (current.cover != nil)
        
        if candidateHasCover && !currentHasCover { return true }
        if !candidateHasCover && currentHasCover { return false }
        
        // 2. Prefer "Series Container" over "Episode" (for Series search)
        if candidate.type == "series" && current.type == "series_episode" { return true }
        if candidate.type == "series_episode" && current.type == "series" { return false }
        
        // 3. Prefer 4K/UHD over standard
        let cQ = candidate.quality ?? ""
        let curQ = current.quality ?? ""
        if cQ.contains("4K") && !curQ.contains("4K") { return true }
        
        return false
    }
    
    private func isGenericTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // REMOVED: 't.count < 3' check which was hiding movies like "Up", "It", "Us"
        return t == "unknown title" || t == "unknown channel" || t == "movie" || t == "series" || t.isEmpty
    }
    
    // MARK: - Legacy / Standard Methods
    
    func findMatches(for titles: [String], limit: Int = 20) -> [Channel] {
        guard !titles.isEmpty else { return [] }
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        let subPredicates = titles.prefix(50).map { NSPredicate(format: "title CONTAINS[cd] %@", $0) }
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subPredicates)
        request.fetchLimit = limit
        return deduplicate(channels: (try? context.fetch(request)) ?? [], isSeries: false)
    }
    
    func getFavorites(type: String) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "isFavorite == YES AND type == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        return deduplicate(channels: (try? context.fetch(request)) ?? [], isSeries: type == "series")
    }
    
    func getRecentlyAdded(type: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = limit * 4
        let raw = (try? context.fetch(request)) ?? []
        return Array(deduplicate(channels: raw, isSeries: type == "series").prefix(limit))
    }
    
    func getRecentFallback(type: String, limit: Int) -> [Channel] {
        return getRecentlyAdded(type: type, limit: limit)
    }
    
    func getByGenre(type: String, groupName: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@ AND group == %@", type, groupName)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        request.fetchLimit = limit * 3
        let raw = (try? context.fetch(request)) ?? []
        return Array(deduplicate(channels: raw, isSeries: type == "series").prefix(limit))
    }
    
    func getSmartContinueWatching(type: String) -> [Channel] {
        let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        request.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
        request.fetchLimit = 50
        
        var results: [Channel] = []
        let nextEpService = NextEpisodeService(context: context)
        
        context.performAndWait {
            guard let history = try? context.fetch(request) else { return }
            var seenUrls = Set<String>()
            
            for item in history {
                if results.count >= 20 { break }
                if seenUrls.contains(item.channelUrl) { continue }
                
                guard let channel = self.getChannel(byUrl: item.channelUrl), channel.type == type else { continue }
                
                let pct = Double(item.duration) > 0 ? Double(item.position) / Double(item.duration) : 0
                
                if channel.type == "movie" {
                    if pct > 0.05 && pct < 0.95 {
                        results.append(channel)
                        seenUrls.insert(channel.url)
                    }
                } else if channel.type == "series" || channel.type == "series_episode" {
                     if pct > 0.95, let next = nextEpService.findNextEpisode(currentChannel: channel) {
                         results.append(next)
                         seenUrls.insert(next.url)
                     } else {
                         results.append(channel)
                         seenUrls.insert(channel.url)
                     }
                } else {
                    results.append(channel)
                    seenUrls.insert(channel.url)
                }
            }
        }
        return results
    }
    
    func getBrowsingContent(playlistUrl: String, type: String, group: String) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        var predicates = [
            NSPredicate(format: "playlistUrl == %@", playlistUrl),
            NSPredicate(format: "type == %@", type)
        ]
        if group != "All" {
            predicates.append(NSPredicate(format: "group == %@", group))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        request.fetchLimit = 1000
        let raw = (try? context.fetch(request)) ?? []
        return deduplicate(channels: raw, isSeries: type == "series")
    }
    
    func getGroups(playlistUrl: String, type: String) -> [String] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Channel")
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type)
        request.propertiesToFetch = ["group"]
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.sortDescriptors = [NSSortDescriptor(key: "group", ascending: true)]
        
        guard let results = try? context.fetch(request) as? [[String: Any]] else { return [] }
        return results.compactMap { $0["group"] as? String }
    }
    
    func getChannel(byUrl url: String) -> Channel? {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
