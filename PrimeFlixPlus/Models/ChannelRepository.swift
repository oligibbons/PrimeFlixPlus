import Foundation
import CoreData

/// The primary Data Access Object (DAO) for fetching Channels.
/// Updated with "Hybrid Search" (Fuzzy Matching) and "Reverse Search" (API Integration).
class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Advanced Search Engine
    
    struct SearchResults {
        let movies: [Channel]
        let series: [Channel]
        let live: [Channel]
        let peopleMatches: [Channel] // Content related to actor/director search (Future use)
    }
    
    struct SearchFilters {
        var only4K: Bool = false
        var onlyLive: Bool = false
        var onlyMovies: Bool = false
        var onlySeries: Bool = false
        
        // Helper to check if any specific filter is active
        var hasActiveFilters: Bool {
            return only4K || onlyLive || onlyMovies || onlySeries
        }
    }
    
    /// The "Hybrid" Search Function.
    /// Performs broad database fetching followed by refined in-memory fuzzy matching.
    func searchHybrid(query: String, filters: SearchFilters) -> SearchResults {
        guard !query.isEmpty else { return SearchResults(movies: [], series: [], live: [], peopleMatches: []) }
        
        let rawTerms = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Optimization: If query is very short (2 chars), use strict prefix to avoid fetching 50k items.
        // Otherwise, use CONTAINS to cast a wide net (e.g. "man" finds "Spider-Man").
        let isShortQuery = rawTerms.count < 3
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        
        // 1. Build Base Predicate (Broad)
        var predicates: [NSPredicate] = []
        
        if isShortQuery {
            predicates.append(NSPredicate(format: "title BEGINSWITH[cd] %@", rawTerms))
        } else {
            // Broad fetch: We refine the ranking in memory using Levenshtein distance
            predicates.append(NSPredicate(format: "title CONTAINS[cd] %@", rawTerms))
        }
        
        // 2. Apply Filters
        if filters.only4K {
            predicates.append(NSPredicate(format: "quality CONTAINS[cd] '4K' OR quality CONTAINS[cd] 'UHD'"))
        }
        
        var typePredicates: [NSPredicate] = []
        if filters.onlyLive { typePredicates.append(NSPredicate(format: "type == 'live'")) }
        if filters.onlyMovies { typePredicates.append(NSPredicate(format: "type == 'movie'")) }
        if filters.onlySeries { typePredicates.append(NSPredicate(format: "type == 'series' OR type == 'series_episode'")) }
        
        if !typePredicates.isEmpty {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        // Optimization: Limit fetch size for performance on older Apple TVs
        request.fetchLimit = 300
        
        var movies: [Channel] = []
        var series: [Channel] = []
        var live: [Channel] = []
        
        context.performAndWait {
            if let results = try? context.fetch(request) {
                // 3. In-Memory Fuzzy Ranking & Deduplication
                let ranked = rankByRelevance(candidates: results, query: rawTerms)
                let deduplicated = deduplicateChannels(ranked)
                
                for ch in deduplicated {
                    if ch.type == "movie" { movies.append(ch) }
                    else if ch.type == "series" || ch.type == "series_episode" { series.append(ch) }
                    else if ch.type == "live" { live.append(ch) }
                }
            }
        }
        
        return SearchResults(movies: movies, series: series, live: live, peopleMatches: [])
    }
    
    // MARK: - Reverse Search Support
    
    /// Finds local channels matching a list of external titles (e.g. from TMDB Actor Credits).
    /// Used when a user clicks "Tom Cruise" -> We search local DB for "Top Gun", "Mission Impossible", etc.
    func findMatches(for titles: [String], limit: Int = 20) -> [Channel] {
        guard !titles.isEmpty else { return [] }
        
        // Optimization: Normalize titles to create a clean set of keywords
        // e.g. "Top Gun: Maverick" -> "Top Gun" (Prefix matching is safer for noisy IPTV titles)
        let cleanTitles = titles.prefix(50).map {
            TitleNormalizer.parse(rawTitle: $0).normalizedTitle
        }
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        
        // Construct a massive OR predicate (SQLite handles this efficiently)
        let subPredicates = cleanTitles.map { NSPredicate(format: "title CONTAINS[cd] %@", $0) }
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subPredicates)
        request.fetchLimit = 100 // Don't over-fetch
        
        var matches: [Channel] = []
        context.performAndWait {
            if let results = try? context.fetch(request) {
                let unique = deduplicateChannels(results)
                
                // Sort by newest added to make the collection feel fresh
                matches = unique.sorted { a, b in
                    (a.addedAt ?? Date.distantPast) > (b.addedAt ?? Date.distantPast)
                }
            }
        }
        
        return Array(matches.prefix(limit))
    }
    
    // MARK: - Internal Ranking Logic
    
    private func rankByRelevance(candidates: [Channel], query: String) -> [Channel] {
        return candidates.sorted { c1, c2 in
            let score1 = TitleNormalizer.similarity(between: query, and: c1.title)
            let score2 = TitleNormalizer.similarity(between: query, and: c2.title)
            
            // If scores are very close, prioritize the "Shortest Title"
            // Explanation: If query is "Hulk", "Hulk" (4 chars) is a better match than "She-Hulk" (8 chars)
            if abs(score1 - score2) < 0.1 {
                return c1.title.count < c2.title.count
            }
            return score1 > score2
        }
    }
    
    // MARK: - Standard Lists (Deduplicated)
    
    func getFavorites(type: String) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "isFavorite == YES AND type == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        
        let raw = (try? context.fetch(request)) ?? []
        return deduplicateChannels(raw)
    }
    
    func getRecentlyAdded(type: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@", type)
        request.sortDescriptors = [
            NSSortDescriptor(key: "addedAt", ascending: false)
        ]
        // Fetch extra to account for deduplication removal
        request.fetchLimit = limit * 4
        
        let raw = (try? context.fetch(request)) ?? []
        return Array(deduplicateChannels(raw).prefix(limit))
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
        return Array(deduplicateChannels(raw).prefix(limit))
    }
    
    // MARK: - Smart Fetching
    
    func getSmartContinueWatching(type: String) -> [Channel] {
        let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        request.predicate = NSPredicate(format: "lastPlayed >= %@", cutoffDate as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
        request.fetchLimit = 50
        
        var results: [Channel] = []
        let nextEpService = NextEpisodeService(context: context)
        
        context.performAndWait {
            guard let history = try? context.fetch(request) else { return }
            var processedSeriesMap = [String: Bool]()
            
            for item in history {
                if results.count >= 20 { break }
                guard let channel = getChannel(byUrl: item.channelUrl), channel.type == type else { continue }
                
                let percentage = Double(item.duration) > 0 ? Double(item.position) / Double(item.duration) : 0
                
                if channel.type == "movie" {
                    if percentage > 0.05 && percentage < 0.95 {
                        results.append(channel)
                    }
                } else if channel.type == "series" || channel.type == "series_episode" {
                    // Use Normalized Title as Key to prevent duplicate entries for same show
                    let info = TitleNormalizer.parse(rawTitle: channel.title)
                    let seriesKey = info.normalizedTitle
                    
                    if processedSeriesMap[seriesKey] == true { continue }
                    
                    if percentage < 0.95 {
                        results.append(channel)
                        processedSeriesMap[seriesKey] = true
                    } else {
                        // Finished? Find next
                        if let nextEp = nextEpService.findNextEpisode(currentChannel: channel) {
                            results.append(nextEp)
                            processedSeriesMap[seriesKey] = true
                        }
                    }
                } else if channel.type == "live" {
                    results.append(channel)
                }
            }
        }
        return results
    }
    
    // MARK: - Navigation & Grouping
    
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
        return deduplicateChannels(raw)
    }
    
    func getGroups(playlistUrl: String, type: String) -> [String] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type)
        request.propertiesToFetch = ["group"]
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.sortDescriptors = [NSSortDescriptor(key: "group", ascending: true)]
        
        guard let results = try? context.fetch(request) as? [[String: Any]] else { return [] }
        return results.compactMap { $0["group"] as? String }
    }
    
    // MARK: - Legacy Search (Preserved for compatibility)
    
    struct LegacySearchResults {
        let movies: [Channel]
        let series: [Channel]
    }
    
    func search(query: String) -> LegacySearchResults {
        guard !query.isEmpty else { return LegacySearchResults(movies: [], series: []) }
        
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "title CONTAINS[cd] %@", normalizedQuery)
        request.fetchLimit = 200
        
        var movies: [Channel] = []
        var series: [Channel] = []
        
        context.performAndWait {
            if let results = try? context.fetch(request) {
                for ch in results {
                    if ch.type == "movie" { movies.append(ch) }
                    else if ch.type == "series" || ch.type == "series_episode" { series.append(ch) }
                }
            }
        }
        
        return LegacySearchResults(movies: deduplicateChannels(movies), series: deduplicateChannels(series))
    }
    
    func searchLiveContent(query: String) -> (categories: [String], channels: [Channel]) {
        guard !query.isEmpty else { return ([], []) }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Search Groups
        let groupReq = NSFetchRequest<NSDictionary>(entityName: "Channel")
        groupReq.resultType = .dictionaryResultType
        groupReq.returnsDistinctResults = true
        groupReq.propertiesToFetch = ["group"]
        groupReq.predicate = NSPredicate(format: "type == 'live' AND group CONTAINS[cd] %@", normalizedQuery)
        
        var groups: [String] = []
        context.performAndWait {
            if let results = try? context.fetch(groupReq) {
                groups = results.compactMap { $0["group"] as? String }
            }
        }
        
        // 2. Search Channels
        let chanReq = NSFetchRequest<Channel>(entityName: "Channel")
        chanReq.predicate = NSPredicate(format: "type == 'live' AND title CONTAINS[cd] %@", normalizedQuery)
        chanReq.fetchLimit = 50
        
        var channels: [Channel] = []
        context.performAndWait {
            channels = (try? context.fetch(chanReq)) ?? []
        }
        
        return (groups, channels)
    }
    
    // MARK: - Helpers
    
    func getChannel(byUrl url: String) -> Channel? {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    // MARK: - Deduplication Engine
    
    /// Groups channels by their `normalizedTitle` and returns the single best version for display.
    private func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var groups: [String: [Channel]] = [:]
        
        // 1. Grouping
        for channel in channels {
            let info = TitleNormalizer.parse(rawTitle: channel.canonicalTitle ?? channel.title)
            // Key is the clean title (e.g. "SEVERANCE")
            let key = info.normalizedTitle.uppercased()
            groups[key, default: []].append(channel)
        }
        
        // 2. Selection (Best Candidate)
        var unique: [Channel] = []
        for (_, variants) in groups {
            // Sort variants to find the "best" one to display
            // Criteria:
            // 1. Has metadata (cover/backdrop)
            // 2. Highest Quality Score
            
            if let best = variants.max(by: { a, b in
                let aHasCover = a.cover != nil
                let bHasCover = b.cover != nil
                if aHasCover != bHasCover { return aHasCover ? false : true } // Prefer existing cover
                
                let infoA = TitleNormalizer.parse(rawTitle: a.canonicalTitle ?? a.title)
                let infoB = TitleNormalizer.parse(rawTitle: b.canonicalTitle ?? b.title)
                return infoA.qualityScore < infoB.qualityScore
            }) {
                unique.append(best)
            }
        }
        
        return unique
    }
}
