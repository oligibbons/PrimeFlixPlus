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
        // Context save is handled by the caller (PrimeFlixRepository)
    }

    // MARK: - Simplified Search Operation
    
    /// A robust, simple search that finds ANY item containing the query string.
    /// Sorts results alphabetically and groups them by type.
    func searchHybrid(query: String, filters: SearchFilters) -> SearchResults {
        let rawTerm = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Return empty if no query and no filters (though typically query won't be empty here)
        if rawTerm.isEmpty && !filters.hasActiveFilters {
            return SearchResults(movies: [], series: [], live: [], peopleMatches: [])
        }
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.fetchLimit = 1000 // Increased limit to ensure we find your files
        
        // 1. Build Predicates
        var predicates: [NSPredicate] = []
        
        // Search Text Predicate (Simple "Contains")
        if !rawTerm.isEmpty {
            // Checks visible title, raw filename/title, or original group
            let titleMatch = NSPredicate(format: "title CONTAINS[cd] %@", rawTerm)
            let rawMatch = NSPredicate(format: "canonicalTitle CONTAINS[cd] %@", rawTerm)
            let groupMatch = NSPredicate(format: "group CONTAINS[cd] %@", rawTerm)
            
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [titleMatch, rawMatch, groupMatch]))
        }
        
        // Filter Predicates
        if filters.onlyMovies {
            predicates.append(NSPredicate(format: "type == 'movie'"))
        }
        if filters.onlySeries {
            predicates.append(NSPredicate(format: "type == 'series' OR type == 'series_episode'"))
        }
        if filters.onlyLive {
            predicates.append(NSPredicate(format: "type == 'live'"))
        }
        
        // Combine all requirements
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        // 2. Sort by Title
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        
        // 3. Execute Fetch
        var results: [Channel] = []
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        
        // 4. Categorize & Deduplicate
        // We use a simplified deduplication to avoid showing 10 versions of the same movie,
        // but it's less aggressive than before to ensure you see your files.
        let distinctItems = deduplicateChannels(results)
        
        var movies: [Channel] = []
        var series: [Channel] = []
        var live: [Channel] = []
        
        for ch in distinctItems {
            if ch.type == "movie" {
                movies.append(ch)
            } else if ch.type == "series" || ch.type == "series_episode" {
                series.append(ch)
            } else if ch.type == "live" {
                live.append(ch)
            }
        }
        
        return SearchResults(movies: movies, series: series, live: live, peopleMatches: [])
    }
    
    // MARK: - Matches & Lookups (Reverse Search)
    
    func findMatches(for titles: [String], limit: Int = 20) -> [Channel] {
        // Simplified to just strict title matching to avoid "Unknown" logic
        guard !titles.isEmpty else { return [] }
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        let subPredicates = titles.prefix(50).map { NSPredicate(format: "title CONTAINS[cd] %@", $0) }
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subPredicates)
        request.fetchLimit = 50
        
        var matches: [Channel] = []
        context.performAndWait {
            matches = (try? context.fetch(request)) ?? []
        }
        return deduplicateChannels(matches)
    }
    
    // MARK: - Standard Lists (Unchanged)
    
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
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
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
                    // Simple series key based on title to avoid over-grouping
                    let seriesKey = channel.title
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
    
    // MARK: - Simplified Deduplication
    
    /// Groups by title and picks the best quality version.
    private func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var groups: [String: [Channel]] = [:]
        
        for channel in channels {
            // Use the simple title as key.
            // If "Unknown Title" is appearing, it's usually because 'title' is empty/nil.
            // Fallback to canonicalTitle if title is suspicious.
            let key = channel.title.count > 2 ? channel.title : (channel.canonicalTitle ?? "Unknown")
            groups[key, default: []].append(channel)
        }
        
        var unique: [Channel] = []
        for (_, variants) in groups {
            // Simple logic: Prefer item with cover art, then 4K, then 1080p
            if let best = variants.sorted(by: { a, b in
                let aCover = (a.cover != nil) ? 1 : 0
                let bCover = (b.cover != nil) ? 1 : 0
                if aCover != bCover { return aCover > bCover }
                
                // If covers equal, prefer "4K" in title/quality
                let aQ = (a.quality ?? "") + a.title
                let bQ = (b.quality ?? "") + b.title
                if aQ.contains("4K") && !bQ.contains("4K") { return true }
                
                return false
            }).first {
                unique.append(best)
            }
        }
        // Return sorted alphabetically
        return unique.sorted { $0.title < $1.title }
    }
}
