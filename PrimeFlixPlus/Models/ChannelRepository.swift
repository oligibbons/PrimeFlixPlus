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
        let livePrograms: [Programme] // Programs matching the query
    }
    
    func search(query: String) -> SearchResults {
        guard !query.isEmpty else {
            return SearchResults(movies: [], series: [], liveChannels: [], livePrograms: [])
        }
        
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Search Channels (Movies, Series, Live)
        let channelReq = NSFetchRequest<Channel>(entityName: "Channel")
        // Case-insensitive, diacritic-insensitive "CONTAINS"
        channelReq.predicate = NSPredicate(format: "title CONTAINS[cd] %@", normalizedQuery)
        // Limit to prevent UI lag on massive libraries
        channelReq.fetchLimit = 50
        
        var movies: [Channel] = []
        var series: [Channel] = []
        var live: [Channel] = []
        
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
        
        // 2. Search EPG (Live TV Guide)
        // Find programs that match the query AND are On Air or Starting Soon
        let epgReq = NSFetchRequest<Programme>(entityName: "Programme")
        
        let now = Date()
        let oneHourLater = now.addingTimeInterval(3600)
        
        // Predicate:
        // (Title matches query) AND
        // (Ends AFTER now) AND (Starts BEFORE 1 hour from now)
        epgReq.predicate = NSPredicate(
            format: "title CONTAINS[cd] %@ AND end > %@ AND start < %@",
            normalizedQuery, now as NSDate, oneHourLater as NSDate
        )
        epgReq.fetchLimit = 20
        epgReq.sortDescriptors = [NSSortDescriptor(key: "start", ascending: true)]
        
        let programs = (try? context.fetch(epgReq)) ?? []
        
        // Deduplicate Series (Optional optimization)
        let uniqueSeries = deduplicateChannels(series)
        
        return SearchResults(
            movies: movies,
            series: uniqueSeries,
            liveChannels: live,
            livePrograms: programs
        )
    }
    
    // MARK: - Smart "Continue Watching" Logic
    
    /// Returns items partially watched (5-95%) or the NEXT episode if finished.
    func getSmartContinueWatching(type: String) -> [Channel] {
        let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        request.predicate = NSPredicate(format: "lastPlayed >= %@", thirtyDaysAgo as NSDate)
        
        request.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
        request.fetchLimit = 100
        
        guard let history = try? context.fetch(request) else { return [] }
        
        var results: [Channel] = []
        var processedSeriesMap = [String: Bool]()
        
        for item in history {
            if results.count >= 20 { break }
            guard let channel = getChannel(byUrl: item.channelUrl), channel.type == type else { continue }
            
            let percentage = Double(item.duration) > 0 ? Double(item.position) / Double(item.duration) : 0
            
            if channel.type == "movie" {
                if percentage > 0.05 && percentage < 0.95 {
                    results.append(channel)
                }
            } else if channel.type == "series" {
                let info = TitleNormalizer.parse(rawTitle: channel.title)
                let seriesKey = info.normalizedTitle
                
                if processedSeriesMap[seriesKey] == true { continue }
                
                if percentage < 0.95 {
                    results.append(channel)
                    processedSeriesMap[seriesKey] = true
                } else {
                    if let nextEp = findNextEpisode(currentChannel: channel) {
                        results.append(nextEp)
                        processedSeriesMap[seriesKey] = true
                    }
                }
            } else if channel.type == "live" {
                results.append(channel)
            }
        }
        return results
    }
    
    private func findNextEpisode(currentChannel: Channel) -> Channel? {
        let raw = currentChannel.title
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
        
        let sIndex = match.numberOfRanges == 5 ? 2 : 1
        let eIndex = match.numberOfRanges == 5 ? 4 : 2
        
        let sRange = match.range(at: sIndex)
        let eRange = match.range(at: eIndex)
        
        guard let s = Int(nsString.substring(with: sRange)),
              let e = Int(nsString.substring(with: eRange)) else { return nil }
        
        return (s, e)
    }
    
    private func findNext(currentChannel: Channel, season: Int, episode: Int) -> Channel? {
        if let next = findEpisodeVariant(original: currentChannel, season: season, episode: episode + 1) {
            return next
        }
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
        
        req.predicate = NSPredicate(
            format: "playlistUrl == %@ AND type == 'series' AND title CONTAINS[cd] %@",
            original.playlistUrl, info.normalizedTitle
        )
        
        guard let candidates = try? context.fetch(req) else { return nil }
        
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
    
    func getTrendingMatches(type: String, tmdbResults: [String]) -> [Channel] {
        var matches: [Channel] = []
        var seenTitles = Set<String>()
        
        for title in tmdbResults {
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
        // Helper to find a Channel based on its Stream ID (used for EPG mapping)
        // This is heuristic because Channel Entity doesn't explicitly store ID separate from URL.
        // We assume the URL contains the ID.
        let request = NSFetchRequest<Channel>(entityName: "Channel")
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
        
        guard let candidates = try? context.fetch(request) else { return [channel] }
        
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
        
        guard let results = try? context.fetch(request) as? [[String: Any]] else { return [] }
        let groups = results.compactMap { $0["group"] as? String }
        return Array(Set(groups)).sorted()
    }
    
    func getFavorites() -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "isFavorite == YES")
        return (try? context.fetch(request)) ?? []
    }
    
    func getRecentAdded(playlistUrl: String, type: String) -> [Channel] {
        return getRecentFallback(type: type, limit: 20)
    }
    
    private func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var uniqueMap = [String: Channel]()
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
