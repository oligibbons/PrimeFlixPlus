import Foundation
import CoreData

/// The primary Data Access Object (DAO) for fetching Channels.
/// Now enforces strict deduplication to ensure "One Show, One Entry" across the app.
class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
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
    
    // MARK: - Search
    
    struct SearchResults {
        let movies: [Channel]
        let series: [Channel]
    }
    
    func search(query: String) -> SearchResults {
        guard !query.isEmpty else { return SearchResults(movies: [], series: []) }
        
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
        
        return SearchResults(movies: deduplicateChannels(movies), series: deduplicateChannels(series))
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
            // 3. Alphabetical
            
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
