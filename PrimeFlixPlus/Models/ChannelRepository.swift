import Foundation
import CoreData

class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Smart "Continue Watching" Logic
    
    func getSmartContinueWatching(type: String) -> [Channel] {
        let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        
        // Rule: Watched in the last 30 days
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
                // Movie: Show if 5% - 95% watched
                if percentage > 0.05 && percentage < 0.95 {
                    results.append(channel)
                }
            } else if channel.type == "series" {
                // Series: Handle Next Episode
                let info = TitleNormalizer.parse(rawTitle: channel.title)
                let seriesKey = info.normalizedTitle
                
                if processedSeriesMap[seriesKey] == true { continue }
                
                if percentage < 0.95 {
                    results.append(channel) // Resume
                    processedSeriesMap[seriesKey] = true
                } else {
                    if let nextEp = findNextEpisode(currentChannel: channel) {
                        results.append(nextEp) // Up Next
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
        // Regex for "S01 E05" or "S1E5"
        let pattern = "(?i)(S)(\\d+)\\s*(E)(\\d+)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = raw as NSString
        let results = regex.matches(in: raw, range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.first, match.numberOfRanges == 5 else { return nil }
        
        guard let s = Int(nsString.substring(with: match.range(at: 2))),
              let e = Int(nsString.substring(with: match.range(at: 4))) else { return nil }
        
        // 1. Try Next Episode
        if let next = findEpisodeVariant(original: currentChannel, season: s, episode: e + 1) { return next }
        // 2. Try Next Season
        if let nextSeason = findEpisodeVariant(original: currentChannel, season: s + 1, episode: 1) { return nextSeason }
        
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
            let t = ch.title.uppercased()
            return t.contains("S\(sPadded)E\(ePadded)") || t.contains("S\(season)E\(episode)")
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
        // Strict 7-day window
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
    
    // MARK: - Basic & Helper
    
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
    
    private func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var uniqueMap = [String: Channel]()
        for channel in channels {
            let info = TitleNormalizer.parse(rawTitle: channel.title)
            let key = info.normalizedTitle.lowercased()
            if uniqueMap[key] == nil { uniqueMap[key] = channel }
        }
        return Array(uniqueMap.values)
    }
    
    // Legacy / Pass-through
    func getVersions(for channel: Channel) -> [Channel] {
        let info = TitleNormalizer.parse(rawTitle: channel.title)
        let targetTitle = info.normalizedTitle.lowercased()
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@", channel.type)
        guard let candidates = try? context.fetch(request) else { return [channel] }
        let variants = candidates.filter {
            TitleNormalizer.parse(rawTitle: $0.title).normalizedTitle.lowercased() == targetTitle
        }
        return variants.isEmpty ? [channel] : variants
    }
    
    func getBrowsingContent(playlistUrl: String, type: String, group: String) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        var predicates = [NSPredicate(format: "playlistUrl == %@", playlistUrl), NSPredicate(format: "type == %@", type)]
        if group != "All" { predicates.append(NSPredicate(format: "group == %@", group)) }
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
        return results.compactMap { $0["group"] as? String }.sorted()
    }
    
    func getFavorites() -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "isFavorite == YES")
        return (try? context.fetch(request)) ?? []
    }
    
    // Added for passthrough compatibility
    func getRecentAdded(playlistUrl: String, type: String) -> [Channel] {
        return getRecentFallback(type: type, limit: 20)
    }

    private func saveContext() {
        if context.hasChanges { try? context.save() }
    }
}
