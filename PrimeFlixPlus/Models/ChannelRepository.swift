import Foundation
import CoreData

class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Smart "Continue Watching" Logic
    
    /// Returns items partially watched (5-95%) or the NEXT episode if finished.
    /// Filters out items not watched in the last 30 days.
    func getSmartContinueWatching(type: String) -> [Channel] {
        let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        
        // Rule: Watched in the last 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        request.predicate = NSPredicate(format: "lastPlayed >= %@", thirtyDaysAgo as NSDate)
        
        request.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
        request.fetchLimit = 100 // Fetch a buffer to account for filtering
        
        guard let history = try? context.fetch(request) else { return [] }
        
        var results: [Channel] = []
        var processedSeriesMap = [String: Bool]() // To avoid duplicates for same series
        
        for item in history {
            // Hard limit to 20 items for the UI
            if results.count >= 20 { break }
            
            // Get the actual channel for this history item
            guard let channel = getChannel(byUrl: item.channelUrl), channel.type == type else { continue }
            
            let percentage = Double(item.duration) > 0 ? Double(item.position) / Double(item.duration) : 0
            
            if channel.type == "movie" {
                // Movies: Show if between 5% and 95% watched (Restored to 0.05)
                if percentage > 0.05 && percentage < 0.95 {
                    results.append(channel)
                }
            } else if channel.type == "series" {
                // Series Logic
                let info = TitleNormalizer.parse(rawTitle: channel.title)
                let seriesKey = info.normalizedTitle // Group by show name
                
                // If we already added this show to the "Continue" row, skip
                if processedSeriesMap[seriesKey] == true { continue }
                
                if percentage < 0.95 {
                    // Not finished? Resume this episode.
                    results.append(channel)
                    processedSeriesMap[seriesKey] = true
                } else {
                    // Finished? Find the NEXT episode.
                    if let nextEp = findNextEpisode(currentChannel: channel) {
                        results.append(nextEp)
                        processedSeriesMap[seriesKey] = true
                    }
                }
            } else if channel.type == "live" {
                // Live TV: Just show recently watched
                results.append(channel)
            }
        }
        
        return results
    }
    
    /// Helper to find next episode (supports S01E01 and 1x01 formats)
    private func findNextEpisode(currentChannel: Channel) -> Channel? {
        let raw = currentChannel.title
        
        // 1. Try S01E05 format
        if let (s, e) = extractSeasonEpisode(from: raw, pattern: "(?i)(S)(\\d+)\\s*(E)(\\d+)") {
            return findNext(currentChannel: currentChannel, season: s, episode: e)
        }
        
        // 2. Try 1x05 format
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
        
        // Handle varying capture groups
        let sIndex = match.numberOfRanges == 5 ? 2 : 1
        let eIndex = match.numberOfRanges == 5 ? 4 : 2
        
        let sRange = match.range(at: sIndex)
        let eRange = match.range(at: eIndex)
        
        guard let s = Int(nsString.substring(with: sRange)),
              let e = Int(nsString.substring(with: eRange)) else { return nil }
        
        return (s, e)
    }
    
    private func findNext(currentChannel: Channel, season: Int, episode: Int) -> Channel? {
        // Try Next Episode in Season
        if let next = findEpisodeVariant(original: currentChannel, season: season, episode: episode + 1) {
            return next
        }
        // Try First Episode of Next Season
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
        
        // Predicate: Same Playlist, Same Type, Title contains Normalized Name
        req.predicate = NSPredicate(
            format: "playlistUrl == %@ AND type == 'series' AND title CONTAINS[cd] %@",
            original.playlistUrl, info.normalizedTitle
        )
        
        guard let candidates = try? context.fetch(req) else { return nil }
        
        // Manual filter for strict Season/Episode match to avoid false positives
        return candidates.first { ch in
            let title = ch.title.uppercased()
            // Check variations: S01E02, S1E2, 1x02
            return title.contains("S\(sPadded)E\(ePadded)") ||
                   title.contains("S\(season)E\(episode)") ||
                   title.contains("\(season)X\(ePadded)")
        }
    }
    
    // MARK: - Smart Categorization
    
    /// Get Favorites filtered by Type
    func getFavorites(type: String) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "isFavorite == YES AND type == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }
    
    /// Get Recently Added (Strict last 7 days)
    func getRecentlyAdded(type: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        request.predicate = NSPredicate(format: "type == %@ AND addedAt >= %@", type, sevenDaysAgo as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = limit
        
        guard let raw = try? context.fetch(request) else { return [] }
        return deduplicateChannels(raw)
    }
    
    /// Fallback for Recently Added (Just the latest N items, regardless of date)
    func getRecentFallback(type: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = limit
        
        guard let raw = try? context.fetch(request) else { return [] }
        return deduplicateChannels(raw)
    }
    
    /// Get items by specific Xtream Group Name (Smart Genres)
    func getByGenre(type: String, groupName: String, limit: Int) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@ AND group CONTAINS[cd] %@", type, groupName)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        request.fetchLimit = limit
        
        guard let raw = try? context.fetch(request) else { return [] }
        return deduplicateChannels(raw)
    }
    
    /// Find local channels that match a list of TMDB Titles
    func getTrendingMatches(type: String, tmdbResults: [String]) -> [Channel] {
        var matches: [Channel] = []
        var seenTitles = Set<String>()
        
        for title in tmdbResults {
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            // Fuzzy match: Database title CONTAINS TMDB title
            req.predicate = NSPredicate(format: "type == %@ AND title CONTAINS[cd] %@", type, title)
            req.fetchLimit = 1 // Just need one match per trending item
            
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
    
    // MARK: - Basic Fetching & Helpers
    
    func getChannel(byUrl url: String) -> Channel? {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    func toggleFavorite(channel: Channel) {
        channel.isFavorite.toggle()
        saveContext()
    }
    
    // MARK: - Versioning & Deduplication
    
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
    
    // Legacy / General Favorites getter
    func getFavorites() -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "isFavorite == YES")
        return (try? context.fetch(request)) ?? []
    }
    
    // Added for passthrough compatibility if needed elsewhere
    func getRecentAdded(playlistUrl: String, type: String) -> [Channel] {
        return getRecentFallback(type: type, limit: 20)
    }
    
    private func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var uniqueMap = [String: Channel]()
        for channel in channels {
            let info = TitleNormalizer.parse(rawTitle: channel.title)
            let key = info.normalizedTitle.lowercased()
            // If we haven't seen this show yet, add it.
            if uniqueMap[key] == nil {
                uniqueMap[key] = channel
            }
        }
        return Array(uniqueMap.values)
    }
    
    private func saveContext() {
        if context.hasChanges {
            try? context.save()
        }
    }
}
