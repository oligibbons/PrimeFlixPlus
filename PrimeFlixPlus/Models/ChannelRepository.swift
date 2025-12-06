import Foundation
import CoreData

class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - "Your Fresh Content" (Killer Feature)
    
    /// Finds new content (Sequels, New Seasons) for franchises the user has interacted with.
    /// NOW UPGRADED: Checks History, Favorites, AND "Loose Mode" Onboarding choices.
    func getFreshFranchiseContent(type: String) -> [Channel] {
        // 1. Identify "Franchises" from History, Favorites, AND Taste Profile
        var franchiseRoots = Set<String>()
        var watchedIds = Set<String>() // Set of URLs we know are watched
        
        context.performAndWait {
            // A. From Watch History (Local Playback)
            let historyReq = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            historyReq.fetchLimit = 100
            if let history = try? context.fetch(historyReq) {
                for item in history {
                    watchedIds.insert(item.channelUrl)
                    if let ch = self.getChannel(byUrl: item.channelUrl), ch.type == type {
                        let root = self.extractFranchiseRoot(from: ch.title)
                        if root.count > 3 { franchiseRoots.insert(root) }
                    }
                }
            }
            
            // B. From Core Data Favorites (Local Library)
            let favReq = NSFetchRequest<Channel>(entityName: "Channel")
            favReq.predicate = NSPredicate(format: "isFavorite == YES AND type == %@", type)
            if let favs = try? context.fetch(favReq) {
                for fav in favs {
                    let root = self.extractFranchiseRoot(from: fav.title)
                    if root.count > 3 { franchiseRoots.insert(root) }
                }
            }
            
            // C. From Taste Profile (Onboarding "Loose Mode" Items) - NEW
            let tasteReq = NSFetchRequest<TasteItem>(entityName: "TasteItem")
            // "Loved" or "Watched" status implies interest in the franchise
            let typePredicate = (type == "series") ? "tv" : "movie"
            tasteReq.predicate = NSPredicate(format: "mediaType == %@ AND (status == 'loved' OR status == 'watched')", typePredicate)
            
            if let tasteItems = try? context.fetch(tasteReq) {
                for item in tasteItems {
                    if let title = item.title {
                        let root = self.extractFranchiseRoot(from: title)
                        if root.count > 3 { franchiseRoots.insert(root) }
                        
                        // Note: We don't have a URL for these loose items, so we can't add to 'watchedIds'.
                        // This means if the user has the file locally but hasn't watched it, it might show up.
                        // Ideally, we would match local content to this ID to exclude it, but for "Fresh Content",
                        // showing the movie they just said they loved is actually okay (it puts it front and center).
                    }
                }
            }
        }
        
        if franchiseRoots.isEmpty { return [] }
        
        // 2. Search for items matching these roots
        var freshContent: [Channel] = []
        let candidatesReq = NSFetchRequest<Channel>(entityName: "Channel")
        candidatesReq.predicate = NSPredicate(format: "type == %@", type)
        candidatesReq.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)] // Prioritize newest
        candidatesReq.fetchLimit = 500 // Optimization cap
        
        context.performAndWait {
            if let candidates = try? context.fetch(candidatesReq) {
                for ch in candidates {
                    // Skip if already watched (Local check)
                    if watchedIds.contains(ch.url) { continue }
                    
                    // Check if it belongs to a known franchise
                    let title = self.extractFranchiseRoot(from: ch.title)
                    
                    // Fuzzy contains check
                    if franchiseRoots.contains(where: { title.localizedCaseInsensitiveContains($0) }) {
                        // Avoid duplicates if multiple roots match
                        if !freshContent.contains(where: { $0.url == ch.url }) {
                            freshContent.append(ch)
                        }
                    }
                    
                    if freshContent.count >= 20 { break }
                }
            }
        }
        
        return freshContent
    }
    
    /// **OPTIMIZED:** Relies on TitleNormalizer to clean technical junk first, then strips
    /// common sequel/subtitle patterns to find the base name for franchise grouping.
    private func extractFranchiseRoot(from title: String) -> String {
        // 1. Get the fully cleaned, normalized title from the single source of truth.
        let info = TitleNormalizer.parse(rawTitle: title)
        var clean = info.normalizedTitle
        
        // 2. Remove Season/Episode markers
        if let range = clean.range(of: " S\\d+", options: .regularExpression) {
            clean = String(clean[..<range.lowerBound])
        }
        
        // 3. Remove Sequel Numbers (e.g. "Iron Man 2" -> "Iron Man")
        if let range = clean.range(of: "\\s\\d+$", options: .regularExpression) {
            clean = String(clean[..<range.lowerBound])
        }
        
        // 4. Remove subtitles (e.g. "Mission: Impossible - Fallout" -> "Mission: Impossible")
        if let range = clean.range(of: "[:\\-]", options: .regularExpression) {
            clean = String(clean[..<range.lowerBound])
        }
        
        return clean.trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - Recommended Logic (Enhanced with Locale Filter)
    
    func getRecommended(type: String) -> [Channel] {
        // 1. Get User's Taste Profile & Region Whitelist
        var preferredGroups = Set<String>()
        var regionalWhitelist = Set<String>()
        
        // NEW: Load Taste Profile Genres
        var onboardingGenres: [String] = []
        
        // Current System Locale
        let systemRegion = Locale.current.regionCode?.uppercased() ?? "US"
        regionalWhitelist.insert(systemRegion)
        
        context.performAndWait {
            // A. Taste Profile (Onboarding)
            let profileReq = NSFetchRequest<TasteProfile>(entityName: "TasteProfile")
            if let profile = try? context.fetch(profileReq).first {
                if let genresStr = profile.selectedGenres {
                    onboardingGenres = genresStr.components(separatedBy: ",")
                }
            }
            
            // B. Analyze History for Regions
            let historyReq = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            historyReq.fetchLimit = 50
            if let history = try? context.fetch(historyReq) {
                for item in history {
                    if let ch = self.getChannel(byUrl: item.channelUrl), ch.type == type {
                        preferredGroups.insert(ch.group)
                        if let prefix = extractRegionPrefix(from: ch.group) {
                            regionalWhitelist.insert(prefix)
                        }
                    }
                }
            }
            
            // C. From Favorites
            let favReq = NSFetchRequest<Channel>(entityName: "Channel")
            favReq.predicate = NSPredicate(format: "isFavorite == YES AND type == %@", type)
            if let favs = try? context.fetch(favReq) {
                for fav in favs {
                    preferredGroups.insert(fav.group)
                    if let prefix = extractRegionPrefix(from: fav.group) {
                        regionalWhitelist.insert(prefix)
                    }
                }
            }
        }
        
        // Logic: If we have Onboarding Genres, we MUST prioritize searching for groups that match them.
        // e.g. If user picked "Sci-Fi", we look for groups containing "Sci-Fi"
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        
        var predicates: [NSPredicate] = [NSPredicate(format: "type == %@", type)]
        
        // Construct sophisticated predicate
        // 1. Match preferred groups OR groups matching onboarding genres
        var groupPredicates: [NSPredicate] = []
        
        if !preferredGroups.isEmpty {
            groupPredicates.append(NSPredicate(format: "group IN %@", preferredGroups))
        }
        
        for genre in onboardingGenres {
            groupPredicates.append(NSPredicate(format: "group CONTAINS[cd] %@", genre))
        }
        
        if !groupPredicates.isEmpty {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: groupPredicates))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = 200
        
        var results: [Channel] = []
        
        context.performAndWait {
            if let candidates = try? context.fetch(request) {
                var seenTitles = Set<String>()
                
                for ch in candidates {
                    if results.count >= 20 { break }
                    
                    // Locale Filter
                    if let prefix = extractRegionPrefix(from: ch.group) {
                        let isGeneric = ["4K", "UHD", "VIP", "VOD", "3D", "HEVC"].contains(prefix)
                        if !isGeneric && !regionalWhitelist.contains(prefix) {
                            continue
                        }
                    }
                    
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
    
    private func extractRegionPrefix(from group: String) -> String? {
        let parts = group.components(separatedBy: CharacterSet(charactersIn: "|:-"))
        if let first = parts.first {
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if trimmed.count >= 2 && trimmed.count <= 3 && trimmed.allSatisfy({ $0.isLetter }) {
                return trimmed
            }
        }
        return nil
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
        
        // Search EPG
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
        
        let uniqueSeries = deduplicateChannels(series)
        
        return SearchResults(
            movies: movies,
            series: uniqueSeries,
            liveChannels: live,
            livePrograms: programs
        )
    }
    
    // MARK: - Live TV Search
    
    func searchLiveContent(query: String) -> (categories: [String], channels: [Channel]) {
        guard !query.isEmpty else { return ([], []) }
        
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let groupRequest = NSFetchRequest<NSDictionary>(entityName: "Channel")
        groupRequest.resultType = .dictionaryResultType
        groupRequest.returnsDistinctResults = true
        groupRequest.propertiesToFetch = ["group"]
        groupRequest.predicate = NSPredicate(format: "type == 'live' AND group CONTAINS[cd] %@", normalizedQuery)
        groupRequest.sortDescriptors = [NSSortDescriptor(key: "group", ascending: true)]
        
        var matchingGroups: [String] = []
        
        context.performAndWait {
            if let results = try? context.fetch(groupRequest) {
                matchingGroups = results.compactMap { $0["group"] as? String }
            }
        }
        
        let channelRequest = NSFetchRequest<Channel>(entityName: "Channel")
        channelRequest.predicate = NSPredicate(format: "type == 'live' AND title CONTAINS[cd] %@", normalizedQuery)
        channelRequest.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        channelRequest.fetchLimit = 50
        
        var matchingChannels: [Channel] = []
        
        context.performAndWait {
            matchingChannels = (try? context.fetch(channelRequest)) ?? []
        }
        
        return (matchingGroups, matchingChannels)
    }
    
    // MARK: - Smart "Continue Watching"
    
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
        if currentChannel.seriesId != nil, currentChannel.season > 0, currentChannel.episode > 0 {
            if let next = findSpecificEpisodeByMetadata(
                playlistUrl: currentChannel.playlistUrl,
                seriesId: currentChannel.seriesId!,
                season: Int(currentChannel.season),
                episode: Int(currentChannel.episode) + 1
            ) {
                return next
            }
            if let nextSeason = findSpecificEpisodeByMetadata(
                playlistUrl: currentChannel.playlistUrl,
                seriesId: currentChannel.seriesId!,
                season: Int(currentChannel.season) + 1,
                episode: 1
            ) {
                return nextSeason
            }
        }
        
        let raw = currentChannel.title
        let (s, e) = ChannelStruct.parseSeasonEpisode(from: raw)
        
        if s > 0 || e > 0 {
            return findNext(currentChannel: currentChannel, season: s, episode: e)
        }
        return nil
    }
    
    private func findSpecificEpisodeByMetadata(playlistUrl: String, seriesId: String, season: Int, episode: Int) -> Channel? {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.predicate = NSPredicate(format: "playlistUrl == %@ AND seriesId == %@ AND season == %d AND episode == %d", playlistUrl, seriesId, season, episode)
        req.fetchLimit = 1
        return try? context.fetch(req).first
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
    
    // MARK: - Standard Helpers
    
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
        if limit > 0 { request.fetchLimit = limit }
        
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
    
    func getVersions(for channel: Channel) -> [Channel] {
        let rawSource = channel.canonicalTitle ?? channel.title
        let info = TitleNormalizer.parse(rawTitle: rawSource)
        let targetTitle = info.normalizedTitle.lowercased()
        let prefix = String(targetTitle.prefix(4))
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(
            format: "type == %@ AND title BEGINSWITH[cd] %@",
            channel.type, prefix
        )
        request.fetchLimit = 100
        
        guard let candidates = try? context.fetch(request) else { return [channel] }
        
        let variants = candidates.filter { candidate in
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
