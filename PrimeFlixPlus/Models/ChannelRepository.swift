import Foundation
import CoreData

class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Recommended Logic (NEW)
    
    func getRecommended(type: String) -> [Channel] {
        // 1. Get User's Taste Profile (Based on History & Favorites)
        var preferredGroups = Set<String>()
        
        context.performAndWait {
            // From History
            let historyReq = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            historyReq.fetchLimit = 50
            if let history = try? context.fetch(historyReq) {
                for item in history {
                    if let ch = self.getChannel(byUrl: item.channelUrl), ch.type == type {
                        preferredGroups.insert(ch.group)
                    }
                }
            }
            
            // From Favorites
            let favReq = NSFetchRequest<Channel>(entityName: "Channel")
            favReq.predicate = NSPredicate(format: "isFavorite == YES AND type == %@", type)
            if let favs = try? context.fetch(favReq) {
                for fav in favs {
                    preferredGroups.insert(fav.group)
                }
            }
        }
        
        if preferredGroups.isEmpty { return [] }
        
        // 2. Fetch Unwatched Items from these Groups
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        
        // Predicate: Matches Type AND Group is in Preferred List
        request.predicate = NSPredicate(format: "type == %@ AND group IN %@", type, preferredGroups)
        
        // Sort: Random-ish (using AddedAt for now as proxy for freshness)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = 100 // Fetch pool
        
        var results: [Channel] = []
        
        context.performAndWait {
            if let candidates = try? context.fetch(request) {
                // Filter out duplicates (versions) and already watched stuff
                // (Simplified: Just taking top 20 distinct titles)
                var seenTitles = Set<String>()
                for ch in candidates {
                    if results.count >= 20 { break }
                    let title = ch.title
                    if !seenTitles.contains(title) {
                        results.append(ch)
                        seenTitles.insert(title)
                    }
                }
            }
        }
        
        return results
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
        
        // 1. Search Channels (Targeting the clean 'title' for best UX)
        let channelReq = NSFetchRequest<Channel>(entityName: "Channel")
        channelReq.predicate = NSPredicate(format: "title CONTAINS[cd] %@", normalizedQuery)
        channelReq.fetchLimit = 50
        
        var movies: [Channel] = []
        var series: [Channel] = []
        var live: [Channel] = []
        
        context.performAndWait {
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
        
        // 2. Search EPG
        let epgReq = NSFetchRequest<Programme>(entityName: "Programme")
        let now = Date()
        let threeHoursLater = now.addingTimeInterval(10800)
        
        epgReq.predicate = NSPredicate(
            format: "title CONTAINS[cd] %@ AND end > %@ AND start < %@",
            normalizedQuery, now as NSDate, threeHoursLater as NSDate
        )
        epgReq.fetchLimit = 20
        epgReq.sortDescriptors = [NSSortDescriptor(key: "start", ascending: true)]
        
        var programs: [Programme] = []
        context.performAndWait {
            programs = (try? context.fetch(epgReq)) ?? []
        }
        
        // 3. Deduplicate Series
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
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        request.predicate = NSPredicate(format: "lastPlayed >= %@", cutoffDate as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
        request.fetchLimit = 50
        
        var results: [Channel] = []
        
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
        let prefix = String(info.normalizedTitle.prefix(5))
        
        req.predicate = NSPredicate(
            format: "playlistUrl == %@ AND type == 'series' AND title BEGINSWITH[cd] %@",
            original.playlistUrl, prefix
        )
        req.fetchLimit = 100
        
        guard let candidates = try? context.fetch(req) else { return nil }
        
        return candidates.first { ch in
            let title = ch.title.uppercased()
            if !ch.title.localizedCaseInsensitiveContains(info.normalizedTitle) { return false }
            
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
        let safeResults = Array(tmdbResults.prefix(20))
        
        for title in safeResults {
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            req.predicate = NSPredicate(format: "type == %@ AND title CONTAINS[cd] %@", type, title)
            req.fetchLimit = 1
            
            if let match = try? context.fetch(req).first {
                // Use canonicalTitle if available for better deduping
                let rawForDedup = match.canonicalTitle ?? match.title
                let norm = TitleNormalizer.parse(rawTitle: rawForDedup).normalizedTitle
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
        request.predicate = NSPredicate(format: "url CONTAINS[cd] '/' + %@ + '.'", channelId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    func toggleFavorite(channel: Channel) {
        channel.isFavorite.toggle()
        saveContext()
    }
    
    // MARK: - CRITICAL PERFORMANCE FIX (Optimized)
    func getVersions(for channel: Channel) -> [Channel] {
        // Use canonicalTitle (Raw) to extract the truest normalized title form.
        // This ensures that "Movie (2020)" and "Movie.2020.mkv" match, even if one was cleaned differently.
        let rawSource = channel.canonicalTitle ?? channel.title
        let info = TitleNormalizer.parse(rawTitle: rawSource)
        let targetTitle = info.normalizedTitle.lowercased()
        
        // 1. Narrow down search using 'title' (Cleaned) index
        let prefix = String(targetTitle.prefix(4))
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(
            format: "type == %@ AND title BEGINSWITH[cd] %@",
            channel.type, prefix
        )
        request.fetchLimit = 100
        
        guard let candidates = try? context.fetch(request) else { return [channel] }
        
        // 2. Precise Filter using Normalizer
        let variants = candidates.filter { candidate in
            // Use candidate's canonicalTitle if available for precision
            let candRaw = candidate.canonicalTitle ?? candidate.title
            let candidateInfo = TitleNormalizer.parse(rawTitle: candRaw)
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
    
    private func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var uniqueMap = [String: Channel]()
        uniqueMap.reserveCapacity(channels.count)
        
        for channel in channels {
            // Use canonicalTitle for deduping to ensure accuracy
            let raw = channel.canonicalTitle ?? channel.title
            let info = TitleNormalizer.parse(rawTitle: raw)
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
