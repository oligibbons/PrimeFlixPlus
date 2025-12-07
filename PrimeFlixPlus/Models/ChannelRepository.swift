import Foundation
import CoreData

/// The primary Data Access Object (DAO) for fetching Channels.
/// Refactored to focus on CRUD operations. Complex logic has been moved to Domain Services.
class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Standard Lists
    
    func getFavorites(type: String) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "isFavorite == YES AND type == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }
    
    func getRecentlyAdded(type: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@", type)
        request.sortDescriptors = [
            NSSortDescriptor(key: "addedAt", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }
    
    func getRecentFallback(type: String, limit: Int) -> [Channel] {
        return getRecentlyAdded(type: type, limit: limit)
    }
    
    func getByGenre(type: String, groupName: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@ AND group == %@", type, groupName)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        request.fetchLimit = limit
        return deduplicateChannels((try? context.fetch(request)) ?? [])
    }
    
    // MARK: - Smart Fetching
    
    /// Logic: Checks WatchHistory. If a series is finished, it asks NextEpisodeService for the next one.
    func getSmartContinueWatching(type: String) -> [Channel] {
        let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        request.predicate = NSPredicate(format: "lastPlayed >= %@", cutoffDate as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
        request.fetchLimit = 50
        
        var results: [Channel] = []
        
        // Initialize the service for series logic
        let nextEpService = NextEpisodeService(context: context)
        
        context.performAndWait {
            guard let history = try? context.fetch(request) else { return }
            var processedSeriesMap = [String: Bool]()
            
            for item in history {
                if results.count >= 20 { break }
                guard let channel = getChannel(byUrl: item.channelUrl), channel.type == type else { continue }
                
                let percentage = Double(item.duration) > 0 ? Double(item.position) / Double(item.duration) : 0
                
                if channel.type == "movie" {
                    // Movie Logic: Resume if between 5% and 95%
                    if percentage > 0.05 && percentage < 0.95 {
                        results.append(channel)
                    }
                } else if channel.type == "series" || channel.type == "series_episode" {
                    // Series Logic: Resume OR Find Next
                    let info = TitleNormalizer.parse(rawTitle: channel.title)
                    // Use seriesId as key if available, else normalized title
                    let seriesKey = channel.seriesId ?? info.normalizedTitle
                    
                    if processedSeriesMap[seriesKey] == true { continue }
                    
                    if percentage < 0.95 {
                        // Resume current episode
                        results.append(channel)
                        processedSeriesMap[seriesKey] = true
                    } else {
                        // Episode finished? Find next.
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
        request.fetchLimit = 500
        
        guard let allChannels = try? context.fetch(request) else { return [] }
        return deduplicateChannels(allChannels)
    }
    
    func getGroups(playlistUrl: String, type: String) -> [String] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type)
        request.propertiesToFetch = ["group"]
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.sortDescriptors = [NSSortDescriptor(key: "group", ascending: true)]
        
        guard let results = try? context.fetch(request) as? [[String: Any]] else { return [] }
        let groups = results.compactMap { $0["group"] as? String }
        return groups
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
        
        // Simple CONTAINS search
        request.predicate = NSPredicate(format: "title CONTAINS[cd] %@", normalizedQuery)
        request.fetchLimit = 100
        
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
        
        return SearchResults(movies: movies, series: deduplicateChannels(series))
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
    
    func toggleFavorite(channel: Channel) {
        channel.isFavorite.toggle()
        try? context.save()
    }
    
    private func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var uniqueMap = [String: Channel]()
        for channel in channels {
            let info = TitleNormalizer.parse(rawTitle: channel.canonicalTitle ?? channel.title)
            var key = info.normalizedTitle.lowercased()
            
            if channel.type == "series_episode" {
                key += "_s\(channel.season)_e\(channel.episode)"
            }
            if uniqueMap[key] == nil { uniqueMap[key] = channel }
        }
        return Array(uniqueMap.values)
    }
}
