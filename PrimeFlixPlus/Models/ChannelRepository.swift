import Foundation
import CoreData

/// The primary Data Access Object (DAO) for fetching Channels.
class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Search Engine Data Structures
    
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

    // MARK: - Core Search Methods (New Logic)
    
    /// Searches Movies and Series with Smart Deduplication.
    /// Logic: Matches Title, File Name (Canonical), or Group.
    func searchLibrary(query: String) -> LibrarySearchResults {
        let rawTerm = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTerm.isEmpty { return LibrarySearchResults(movies: [], series: []) }
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.fetchLimit = 1000
        
        // Predicates: Match visible Title OR raw Filename OR Group
        let textMatch = NSPredicate(format: "title CONTAINS[cd] %@ OR canonicalTitle CONTAINS[cd] %@ OR group CONTAINS[cd] %@", rawTerm, rawTerm, rawTerm)
        let typeMatch = NSPredicate(format: "type IN {'movie', 'series', 'series_episode'}")
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [textMatch, typeMatch])
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        
        var results: [Channel] = []
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        
        // Separation
        let rawMovies = results.filter { $0.type == "movie" }
        // Note: We search 'series_episode' too, just in case the container title didn't match but an episode did
        let rawSeries = results.filter { $0.type == "series" || $0.type == "series_episode" }
        
        // Smart Deduplication
        let uniqueMovies = deduplicate(channels: rawMovies, isSeries: false)
        let uniqueSeries = deduplicate(channels: rawSeries, isSeries: true)
        
        return LibrarySearchResults(movies: uniqueMovies, series: uniqueSeries)
    }
    
    /// Searches Live TV Channels and Categories.
    /// Logic: Returns matching Channels AND matching Categories.
    func searchLive(query: String) -> LiveSearchResults {
        let rawTerm = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTerm.isEmpty { return LiveSearchResults(categories: [], channels: []) }
        
        // A. Search Channels
        let channelReq = NSFetchRequest<Channel>(entityName: "Channel")
        channelReq.fetchLimit = 500
        channelReq.predicate = NSPredicate(
            format: "type == 'live' AND (title CONTAINS[cd] %@ OR group CONTAINS[cd] %@ OR canonicalTitle CONTAINS[cd] %@)",
            rawTerm, rawTerm, rawTerm
        )
        channelReq.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        
        var channels: [Channel] = []
        context.performAndWait {
            channels = (try? context.fetch(channelReq)) ?? []
        }
        
        // B. Search Categories (Distinct Groups)
        let distinctGroupReq = NSFetchRequest<NSDictionary>(entityName: "Channel")
        distinctGroupReq.resultType = .dictionaryResultType
        distinctGroupReq.returnsDistinctResults = true
        distinctGroupReq.propertiesToFetch = ["group"]
        distinctGroupReq.predicate = NSPredicate(format: "type == 'live' AND group CONTAINS[cd] %@", rawTerm)
        distinctGroupReq.sortDescriptors = [NSSortDescriptor(key: "group", ascending: true)]
        
        var categories: [String] = []
        context.performAndWait {
            if let dicts = try? context.fetch(distinctGroupReq) as? [[String: String]] {
                categories = dicts.compactMap { $0["group"] }
            }
        }
        
        return LiveSearchResults(categories: categories, channels: channels)
    }
    
    // MARK: - Smart Deduplication Logic (The Fix)
    
    /// Groups duplicates (e.g. 4K vs 1080p) BUT ensures generic titles remain unique.
    private func deduplicate(channels: [Channel], isSeries: Bool) -> [Channel] {
        var unique: [Channel] = []
        var seenKeys = Set<String>()
        
        for item in channels {
            var key = item.title.lowercased()
            
            // CRITICAL FIX: If title is generic (e.g. "Unknown Title"), use the filename/URL as the key.
            // This prevents 100 items named "Unknown Title" from being hidden as duplicates.
            if isGenericTitle(item.title) {
                key = (item.canonicalTitle ?? item.url).lowercased()
            } else if isSeries {
                // For series, group by SeriesID (if structured) to merge seasons/episodes into one Show result
                if let sid = item.seriesId, sid != "0", !sid.isEmpty {
                    key = "sid_\(sid)"
                }
            }
            
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                unique.append(item)
            }
        }
        
        return unique
    }
    
    private func isGenericTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == "unknown title" || t == "unknown channel" || t == "movie" || t == "series" || t.isEmpty || t.count < 3
    }
    
    // MARK: - Reverse Lookup (Matches)
    
    func findMatches(for titles: [String], limit: Int = 20) -> [Channel] {
        guard !titles.isEmpty else { return [] }
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        // Check only the first 50 titles to prevent query explosion
        let subPredicates = titles.prefix(50).map { NSPredicate(format: "title CONTAINS[cd] %@", $0) }
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subPredicates)
        request.fetchLimit = 50
        var matches: [Channel] = []
        context.performAndWait { matches = (try? context.fetch(request)) ?? [] }
        return deduplicate(channels: matches, isSeries: false)
    }
    
    // MARK: - Standard List Accessors
    
    func getFavorites(type: String) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "isFavorite == YES AND type == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        let raw = (try? context.fetch(request)) ?? []
        // Favorites are user-curated, minimal deduplication needed, but good to be safe
        return deduplicate(channels: raw, isSeries: type == "series")
    }
    
    func getRecentlyAdded(type: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = limit * 4 // Fetch more to allow for dedup reduction
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
    
    // MARK: - Smart Fetching
    
    func getSmartContinueWatching(type: String) -> [Channel] {
        let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        request.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
        request.fetchLimit = 50
        
        var results: [Channel] = []
        let nextEpService = NextEpisodeService(context: context)
        
        context.performAndWait {
            guard let history = try? context.fetch(request) else { return }
            var seenUrls = Set<String>()
            var processedSeriesMap = [String: Bool]()
            
            for item in history {
                if results.count >= 20 { break }
                if seenUrls.contains(item.channelUrl) { continue }
                
                guard let channel = self.getChannel(byUrl: item.channelUrl), channel.type == type else { continue }
                
                let percentage = Double(item.duration) > 0 ? Double(item.position) / Double(item.duration) : 0
                
                if channel.type == "movie" {
                    // Movies: Show if 5% < watched < 95%
                    if percentage > 0.05 && percentage < 0.95 {
                        results.append(channel)
                        seenUrls.insert(channel.url)
                    }
                } else if channel.type == "series" || channel.type == "series_episode" {
                    // Series: Group by Title to avoid showing 5 episodes of same show
                    let seriesKey = channel.title
                    if processedSeriesMap[seriesKey] == true { continue }
                    
                    if percentage < 0.95 {
                        // Resume current episode
                        results.append(channel)
                        seenUrls.insert(channel.url)
                        processedSeriesMap[seriesKey] = true
                    } else {
                        // Fetch Next Episode
                        if let nextEp = nextEpService.findNextEpisode(currentChannel: channel) {
                            results.append(nextEp)
                            seenUrls.insert(nextEp.url)
                            processedSeriesMap[seriesKey] = true
                        }
                    }
                } else if channel.type == "live" {
                    results.append(channel)
                    seenUrls.insert(channel.url)
                }
            }
        }
        return results
    }
    
    // MARK: - Navigation & Drill Down
    
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
