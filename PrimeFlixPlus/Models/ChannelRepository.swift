import Foundation
import CoreData

class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Search Logic
    
    struct SearchResults {
        let movies: [Channel]
        let series: [Channel]
        let liveChannels: [Channel]
        let livePrograms: [Programme]
    }
    
    func search(query: String) -> SearchResults {
        guard !query.isEmpty else {
            return SearchResults(movies: [], series: [], liveChannels: [], livePrograms: [])
        }
        
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Search Channels (Movies, Series, Live)
        // Optimization: Fetch only necessary objectIDs first if needed, but for <50 items, objects are fine.
        let channelReq = NSFetchRequest<Channel>(entityName: "Channel")
        channelReq.predicate = NSPredicate(format: "title CONTAINS[cd] %@", normalizedQuery)
        channelReq.fetchLimit = 50 // Strict limit to prevent UI lockup
        
        var movies: [Channel] = []
        var series: [Channel] = []
        var live: [Channel] = []
        
        // Use autoreleasepool to ensure temporary objects from the fetch are cleared immediately
        context.performAndWait {
            autoreleasepool {
                if let channels = try? context.fetch(channelReq) {
                    for ch in channels {
                        switch ch.type {
                        case "movie": movies.append(ch)
                        case "series": series.append(ch)
                        case "live": live.append(ch)
                        default: break
                        }
                    }
                }
            }
        }
        
        // 2. Search EPG (Live TV Guide)
        let epgReq = NSFetchRequest<Programme>(entityName: "Programme")
        let now = Date()
        let oneHourLater = now.addingTimeInterval(3600)
        
        // Optimization: Index 'title', 'start', and 'end' in Core Data Model for this to be fast
        epgReq.predicate = NSPredicate(
            format: "title CONTAINS[cd] %@ AND end > %@ AND start < %@",
            normalizedQuery, now as NSDate, oneHourLater as NSDate
        )
        epgReq.fetchLimit = 20
        epgReq.sortDescriptors = [NSSortDescriptor(key: "start", ascending: true)]
        
        let programs = (try? context.fetch(epgReq)) ?? []
        
        // 3. Deduplicate Series (Heavy operation optimized by TitleNormalizer)
        let uniqueSeries = deduplicateChannels(series)
        
        return SearchResults(
            movies: movies,
            series: uniqueSeries,
            liveChannels: live,
            livePrograms: programs
        )
    }
    
    // MARK: - Smart "Continue Watching" Logic
    
    func getSmartContinueWatching(type: String) -> [Channel] {
        let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        
        // Only fetch items watched in the last 60 days to keep query fast
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        request.predicate = NSPredicate(format: "lastPlayed >= %@", cutoffDate as NSDate)
        
        request.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
        request.fetchLimit = 100
        
        guard let history = try? context.fetch(request) else { return [] }
        
        var results: [Channel] = []
        var processedSeriesMap = [String: Bool]()
        
        // Perform heavy logic in autoreleasepool
        autoreleasepool {
            for item in history {
                if results.count >= 20 { break }
                guard let channel = getChannel(byUrl: item.channelUrl), channel.type == type else { continue }
                
                let percentage = Double(item.duration) > 0 ? Double(item.position) / Double(item.duration) : 0
                
                if channel.type == "movie" {
                    // Movies: Show if between 5% and 95% watched
                    if percentage > 0.05 && percentage < 0.95 {
                        results.append(channel)
                    }
                } else if channel.type == "series" {
                    // Series: Complex logic to find next episode
                    let info = TitleNormalizer.parse(rawTitle: channel.title)
                    let seriesKey = info.normalizedTitle
                    
                    if processedSeriesMap[seriesKey] == true { continue }
                    
                    if percentage < 0.95 {
                        results.append(channel)
                        processedSeriesMap[seriesKey] = true
                    } else {
                        // If finished, try to find the next episode
                        if let nextEp = findNextEpisode(currentChannel: channel) {
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
    
    private func findNextEpisode(currentChannel: Channel) -> Channel? {
        let raw = currentChannel.title
        // Optimized regex patterns via TitleNormalizer knowledge
        if let (s, e) = extractSeasonEpisode(from: raw, pattern: "(?i)(S)(\\d+)\\s*(E)(\\d+)") {
            return findNext(currentChannel: currentChannel, season: s, episode: e)
        }
        if let (s, e) = extractSeasonEpisode(from: raw, pattern: "(\\d+)x(\\d+)") {
            return findNext(currentChannel: currentChannel, season: s, episode: e)
        }
        return nil
    }
    
    private func extractSeasonEpisode(from title: String, pattern: String) -> (Int, Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = title as NSString
        let results = regex.matches(in: title, range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.first, match.numberOfRanges >= 3 else { return nil }
        
        // Handle varying regex group capture indices
        let sIndex = match.numberOfRanges == 5 ? 2 : 1
        let eIndex = match.numberOfRanges == 5 ? 4 : 2
        
        let sRange = match.range(at: sIndex)
        let eRange = match.range(at: eIndex)
        
        guard let s = Int(nsString.substring(with: sRange)),
              let e = Int(nsString.substring(with: eRange)) else { return nil }
        
        return (s, e)
    }
    
    private func findNext(currentChannel: Channel, season: Int, episode: Int) -> Channel? {
        // 1. Try next episode in current season
        if let next = findEpisodeVariant(original: currentChannel, season: season, episode: episode + 1) {
            return next
        }
        // 2. Try first episode of next season
        if let nextSeason = findEpisodeVariant(original: currentChannel, season: season + 1, episode: 1) {
            return nextSeason
        }
        return nil
    }
    
    private func findEpisodeVariant(original: Channel, season: Int, episode: Int) -> Channel? {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        let sPadded = String(format: "%02d", season)
        let ePadded = String(format: "%02d", episode)
        let info = TitleNormalizer.parse(rawTitle: original.title)
        
        // Fetch candidates from the same playlist/series
        req.predicate = NSPredicate(
            format: "playlistUrl == %@ AND type == 'series' AND title CONTAINS[cd] %@",
            original.playlistUrl, info.normalizedTitle
        )
        // Optimization: Limit fetch to reduce memory usage, assuming series aren't infinitely long
        req.fetchLimit = 50
        
        guard let candidates = try? context.fetch(req) else { return nil }
        
        // In-memory filter is faster for complex regex checks than Core Data predicates
        return candidates.first { ch in
            let title = ch.title.uppercased()
            return title.contains("S\(sPadded)E\(ePadded)") ||
                   title.contains("S\(season)E\(episode)") ||
                   title.contains("\(season)X\(ePadded)")
        }
    }
    
    // MARK: - Smart Categorization
    
    func getFavorites(type: String) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "isFavorite == YES AND type == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }
    
    func getRecentlyAdded(type: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        request.predicate = NSPredicate(format: "type == %@ AND addedAt >= %@", type, sevenDaysAgo as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = limit
        
        guard let raw = try? context.fetch(request) else { return [] }
        return deduplicateChannels(raw)
    }
    
    func getRecentFallback(type: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = limit
        
        guard let raw = try? context.fetch(request) else { return [] }
        return deduplicateChannels(raw)
    }
    
    func getByGenre(type: String, groupName: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@ AND group CONTAINS[cd] %@", type, groupName)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        request.fetchLimit = limit
        
        guard let raw = try? context.fetch(request) else { return [] }
        return deduplicateChannels(raw)
    }
    
    // MARK: - Trending
    
    // This was the method missing in your build error.
    // It is used by HomeViewModel to map TMDB Trending Titles -> Local Channels.
    func getTrendingMatches(type: String, tmdbResults: [String]) -> [Channel] {
        var matches: [Channel] = []
        var seenTitles = Set<String>()
        
        // This is expensive, so we limit the input size
        let safeResults = Array(tmdbResults.prefix(20))
        
        for title in safeResults {
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            req.predicate = NSPredicate(format: "type == %@ AND title CONTAINS[cd] %@", type, title)
            req.fetchLimit = 1
            
            if let match = try? context.fetch(req).first {
                let norm = TitleNormalizer.parse(rawTitle: match.title).normalizedTitle
                if !seenTitles.contains(norm) {
                    matches.append(match)
                    seenTitles.insert(norm)
                }
            }
        }
        return matches
    }
    
    // MARK: - Basic Fetching
    
    func getChannel(byUrl url: String) -> Channel? {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    func getChannel(byId channelId: String) -> Channel? {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        // Optimization: Use BeginsWith or Contains depending on ID format
        request.predicate = NSPredicate(format: "url CONTAINS[cd] '/' + %@ + '.'", channelId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    func toggleFavorite(channel: Channel) {
        channel.isFavorite.toggle()
        saveContext()
    }
    
    func getVersions(for channel: Channel) -> [Channel] {
        let info = TitleNormalizer.parse(rawTitle: channel.title)
        let targetTitle = info.normalizedTitle.lowercased()
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@", channel.type)
        
        // Fetch potential candidates first (e.g. by same first letter) to avoid scanning whole DB?
        // For now, scanning is risky on large DBs. Ideally, we would add a 'normalizedTitleHash' to Core Data.
        // Fallback to basic fetch.
        
        guard let candidates = try? context.fetch(request) else { return [channel] }
        
        // Filter in memory using optimized Normalizer
        let variants = candidates.filter { candidate in
            let candidateInfo = TitleNormalizer.parse(rawTitle: candidate.title)
            return candidateInfo.normalizedTitle.lowercased() == targetTitle
        }
        return variants.isEmpty ? [channel] : variants
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
    
    private func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var uniqueMap = [String: Channel]()
        // Reserve capacity to avoid resizing overhead
        uniqueMap.reserveCapacity(channels.count)
        
        for channel in channels {
            let info = TitleNormalizer.parse(rawTitle: channel.title)
            let key = info.normalizedTitle.lowercased()
            if uniqueMap[key] == nil {
                uniqueMap[key] = channel
            }
        }
        return Array(uniqueMap.values)
    }
    
    private func saveContext() {
        if context.hasChanges { try? context.save() }
    }
}
