import Foundation
import CoreData

/// The primary Data Access Object (DAO) for fetching Channels.
class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Search Engine Data Structures
    
    struct SearchResults {
        let movies: [Channel]
        let series: [Channel]
        let live: [Channel]
        let peopleMatches: [Channel]
    }
    
    struct SearchFilters {
        var only4K: Bool = false
        var onlyLive: Bool = false
        var onlyMovies: Bool = false
        var onlySeries: Bool = false
        
        var hasActiveFilters: Bool {
            return only4K || onlyLive || onlyMovies || onlySeries
        }
    }
    
    // MARK: - Core Mutators
    
    func toggleFavorite(_ channel: Channel) {
        channel.isFavorite.toggle()
        // Note: Caller (PrimeFlixRepository) handles the save context.save()
    }

    // MARK: - Search Operations
    
    /// The "Hybrid" Search Function.
    /// 1. Tries a "Tokenized AND" search (Strict but flexible order).
    /// 2. If no results, falls back to "Tokenized OR" (Broad) + Fuzzy Sorting.
    func searchHybrid(query: String, filters: SearchFilters) -> SearchResults {
        // 1. Basic Validation
        let rawTerms = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTerms.isEmpty || filters.hasActiveFilters else {
            return SearchResults(movies: [], series: [], live: [], peopleMatches: [])
        }
        
        // 2. Prepare Tokens
        // "Batman Begins" -> ["Batman", "Begins"]
        let tokens = rawTerms.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        
        // 3. Build Predicate (Stage 1: Strict Token Match)
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.fetchLimit = 400 // Cap fetch to prevent OOM
        
        var baseSubPredicates: [NSPredicate] = []
        
        // Filter Logic
        if filters.only4K {
            baseSubPredicates.append(NSPredicate(format: "quality CONTAINS[cd] '4K' OR quality CONTAINS[cd] 'UHD'"))
        }
        
        var typePredicates: [NSPredicate] = []
        if filters.onlyLive { typePredicates.append(NSPredicate(format: "type == 'live'")) }
        if filters.onlyMovies { typePredicates.append(NSPredicate(format: "type == 'movie'")) }
        if filters.onlySeries { typePredicates.append(NSPredicate(format: "type == 'series' OR type == 'series_episode'")) }
        
        if !typePredicates.isEmpty {
            baseSubPredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates))
        }
        
        // Title Logic (AND)
        // Title must contain Token A AND Token B
        var titlePredicates: [NSPredicate] = []
        for token in tokens {
            titlePredicates.append(NSPredicate(format: "title CONTAINS[cd] %@", token))
        }
        
        // Combine: (Filters) AND (Token A AND Token B)
        var strictPredicates = baseSubPredicates
        strictPredicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: titlePredicates))
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: strictPredicates)
        
        var results: [Channel] = []
        
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        
        // 4. Fallback Logic (Stage 2: Fuzzy / OR Match)
        // If strict search returned nothing, try matching ANY token
        if results.isEmpty && tokens.count > 1 {
            var loosePredicates = baseSubPredicates
            
            // Title must contain Token A OR Token B
            let orTitlePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: titlePredicates)
            loosePredicates.append(orTitlePredicate)
            
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: loosePredicates)
            
            context.performAndWait {
                results = (try? context.fetch(request)) ?? []
            }
        }
        
        // 5. In-Memory Ranking & Categorization
        // We perform fuzzy sorting here because Core Data cannot do Levenshtein distance
        let ranked = self.rankByRelevance(candidates: results, query: rawTerms)
        let deduplicated = self.deduplicateChannels(ranked)
        
        var movies: [Channel] = []
        var series: [Channel] = []
        var live: [Channel] = []
        
        for ch in deduplicated {
            if ch.type == "movie" { movies.append(ch) }
            else if ch.type == "series" || ch.type == "series_episode" { series.append(ch) }
            else if ch.type == "live" { live.append(ch) }
        }
        
        return SearchResults(movies: movies, series: series, live: live, peopleMatches: [])
    }
    
    /// Finds local channels matching a list of external titles (Reverse Search).
    func findMatches(for titles: [String], limit: Int = 20) -> [Channel] {
        guard !titles.isEmpty else { return [] }
        
        // Map external titles to normalized versions for matching noisy IPTV titles
        let cleanTitles = titles.prefix(50).map {
            TitleNormalizer.parse(rawTitle: $0).normalizedTitle
        }
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        
        // Construct an OR predicate for all target titles
        let subPredicates = cleanTitles.map { NSPredicate(format: "title CONTAINS[cd] %@", $0) }
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subPredicates)
        request.fetchLimit = 100 // Don't over-fetch
        
        var matches: [Channel] = []
        context.performAndWait {
            if let results = try? context.fetch(request) {
                let unique = self.deduplicateChannels(results)
                
                // Sort results by newest added to make the collection feel fresh
                matches = unique.sorted { a, b in
                    (a.addedAt ?? Date.distantPast) > (b.addedAt ?? Date.distantPast)
                }
            }
        }
        
        return Array(matches.prefix(limit))
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
                    let info = TitleNormalizer.parse(rawTitle: channel.title)
                    let seriesKey = info.normalizedTitle
                    
                    if processedSeriesMap[seriesKey] == true { continue }
                    
                    if percentage < 0.95 {
                        results.append(channel)
                        processedSeriesMap[seriesKey] = true
                    } else {
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
    
    // FIXED: Changed `type` to String to allow callers to pass `type.rawValue` directly
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
    
    // MARK: - Helpers
    
    func getChannel(byUrl url: String) -> Channel? {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    // MARK: - Deduplication Engine
    
    private func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var groups: [String: [Channel]] = [:]
        
        for channel in channels {
            let info = TitleNormalizer.parse(rawTitle: channel.canonicalTitle ?? channel.title)
            let key = info.normalizedTitle.uppercased()
            groups[key, default: []].append(channel)
        }
        
        var unique: [Channel] = []
        for (_, variants) in groups {
            if let best = variants.max(by: { a, b in
                let aHasCover = (a.cover != nil && !a.cover!.isEmpty)
                let bHasCover = (b.cover != nil && !b.cover!.isEmpty)
                
                if aHasCover != bHasCover {
                    return !aHasCover
                }
                
                let aIsSeries = (a.type == "series")
                let bIsSeries = (b.type == "series")
                
                if aIsSeries != bIsSeries {
                    return !aIsSeries
                }
                
                let infoA = TitleNormalizer.parse(rawTitle: a.canonicalTitle ?? a.title)
                let infoB = TitleNormalizer.parse(rawTitle: b.canonicalTitle ?? b.title)
                
                return infoA.qualityScore < infoB.qualityScore
            }) {
                unique.append(best)
            }
        }
        
        return unique
    }
    
    private func rankByRelevance(candidates: [Channel], query: String) -> [Channel] {
        return candidates.sorted { c1, c2 in
            let score1 = TitleNormalizer.similarity(between: query, and: c1.title)
            let score2 = TitleNormalizer.similarity(between: query, and: c2.title)
            
            if abs(score1 - score2) < 0.1 {
                let c1HasCover = (c1.cover != nil && !c1.cover!.isEmpty)
                let c2HasCover = (c2.cover != nil && !c2.cover!.isEmpty)
                if c1HasCover != c2HasCover {
                    return c1HasCover
                }
                return c1.title.count < c2.title.count
            }
            return score1 > score2
        }
    }
}
