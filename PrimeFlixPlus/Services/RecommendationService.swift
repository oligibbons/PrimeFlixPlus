import Foundation
import CoreData

/// Service responsible for personalized content discovery.
/// Handles "Fresh Content" (Sequels), "Recommended" (Genre/Region matching), and "Trending" (API mapping).
class RecommendationService {
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - "Your Fresh Content" Engine
    
    /// Finds new content (Sequels, New Seasons) for franchises the user has interacted with.
    /// Checks History, Favorites, AND "Loose Mode" Onboarding choices.
    func getFreshFranchiseContent(type: String) -> [Channel] {
        var franchiseRoots = Set<String>()
        var watchedIds = Set<String>() // Set of URLs we know are watched/local
        
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
            
            // C. From Taste Profile (Onboarding "Loose Mode" Items)
            let tasteReq = NSFetchRequest<TasteItem>(entityName: "TasteItem")
            let typePredicate = (type == "series") ? "tv" : "movie"
            tasteReq.predicate = NSPredicate(format: "mediaType == %@ AND status IN {'watched', 'loved', 'super_loved'}", typePredicate)
            
            if let tasteItems = try? context.fetch(tasteReq) {
                for item in tasteItems {
                    if let title = item.title {
                        let root = self.extractFranchiseRoot(from: title)
                        if root.count > 3 { franchiseRoots.insert(root) }
                    }
                }
            }
        }
        
        if franchiseRoots.isEmpty { return [] }
        
        // 2. Search for items matching these roots
        var freshContent: [Channel] = []
        let candidatesReq = NSFetchRequest<Channel>(entityName: "Channel")
        candidatesReq.predicate = NSPredicate(format: "type == %@", type)
        candidatesReq.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        candidatesReq.fetchLimit = 500
        
        context.performAndWait {
            if let candidates = try? context.fetch(candidatesReq) {
                for ch in candidates {
                    if watchedIds.contains(ch.url) { continue }
                    
                    let title = self.extractFranchiseRoot(from: ch.title)
                    
                    if franchiseRoots.contains(where: { self.isStrictMatch(root: $0, candidate: title) }) {
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
    
    // MARK: - Recommendation Engine
    
    func getRecommended(type: String) -> [Channel] {
        var preferredGroups = Set<String>()
        var regionalWhitelist = Set<String>()
        var onboardingGenres: [String] = []
        
        let systemRegion = Locale.current.regionCode?.uppercased() ?? "US"
        regionalWhitelist.insert(systemRegion)
        
        let userLang = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "English"
        
        context.performAndWait {
            // A. Taste Profile
            let profileReq = NSFetchRequest<TasteProfile>(entityName: "TasteProfile")
            if let profile = try? context.fetch(profileReq).first {
                if let genresStr = profile.selectedGenres {
                    onboardingGenres = genresStr.components(separatedBy: ",")
                }
            }
            
            // B. History Analysis (Enhanced for 50% Rule)
            let historyReq = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            // Fetch enough history to determine series progress
            historyReq.fetchLimit = 200
            
            if let history = try? context.fetch(historyReq) {
                // Batch fetch channels to avoid N+1
                let urls = history.map { $0.channelUrl }
                let chReq = NSFetchRequest<Channel>(entityName: "Channel")
                chReq.predicate = NSPredicate(format: "url IN %@", urls)
                let channels = (try? context.fetch(chReq)) ?? []
                let channelMap = Dictionary(uniqueKeysWithValues: channels.map { ($0.url, $0) })
                
                // Track Series Progress: "SeriesID_SeasonNum" -> Set<EpisodeURL>
                var seasonProgress: [String: Set<String>] = [:]
                
                for item in history {
                    guard let ch = channelMap[item.channelUrl], ch.type == type else { continue }
                    
                    let progress = Double(item.duration) > 0 ? Double(item.position) / Double(item.duration) : 0
                    
                    // Logic for Movies: > 50% watched
                    if type == "movie" {
                        if progress > 0.5 {
                            preferredGroups.insert(ch.group)
                            if let prefix = extractRegionPrefix(from: ch.group) {
                                regionalWhitelist.insert(prefix)
                            }
                        }
                    }
                    // Logic for Series: Accumulate watched episodes (> 50% progress each)
                    else if type == "series" {
                        if progress > 0.5 {
                            if let sid = ch.seriesId, !sid.isEmpty {
                                let key = "\(sid)_\(ch.season)"
                                seasonProgress[key, default: []].insert(ch.url)
                            }
                        }
                    }
                }
                
                // Finalize Series Logic: Check "More than half of episodes in a single season"
                if type == "series" {
                    for (key, watchedEps) in seasonProgress {
                        let parts = key.components(separatedBy: "_")
                        guard parts.count == 2, let seasonNum = Int(parts[1]) else { continue }
                        let sid = parts[0]
                        
                        // Count total episodes for this season in DB
                        let countReq = NSFetchRequest<Channel>(entityName: "Channel")
                        countReq.predicate = NSPredicate(format: "seriesId == %@ AND season == %d AND type == 'series_episode'", sid, seasonNum)
                        let total = (try? context.count(for: countReq)) ?? 0
                        
                        // Rule: Watched > 50% of season
                        if total > 0 && Double(watchedEps.count) / Double(total) > 0.5 {
                            // Find a representative channel to extract Group/Region info
                            if let sampleUrl = watchedEps.first, let ch = channelMap[sampleUrl] {
                                preferredGroups.insert(ch.group)
                                if let prefix = extractRegionPrefix(from: ch.group) {
                                    regionalWhitelist.insert(prefix)
                                }
                            }
                        }
                    }
                }
            }
            
            // C. Favorites Analysis
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
        
        // Execute Search with preferences
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        var predicates: [NSPredicate] = [NSPredicate(format: "type == %@", type)]
        
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
                    
                    // Strict Language Filter
                    if CategoryPreferences.shared.isForeign(group: ch.group, language: userLang) {
                        continue
                    }
                    
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
    
    // MARK: - Trending Engine
    
    func getTrendingMatches(type: String, tmdbResults: [String]) -> [Channel] {
        var matches: [Channel] = []
        var seenTitles = Set<String>()
        
        for title in tmdbResults {
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
    
    // MARK: - Private Helpers
    
    private func getChannel(byUrl url: String) -> Channel? {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    private func extractFranchiseRoot(from title: String) -> String {
        let info = TitleNormalizer.parse(rawTitle: title)
        var clean = info.normalizedTitle
        
        if let range = clean.range(of: " S\\d+", options: .regularExpression) {
            clean = String(clean[..<range.lowerBound])
        }
        if let range = clean.range(of: "\\s\\d+$", options: .regularExpression) {
            clean = String(clean[..<range.lowerBound])
        }
        if let range = clean.range(of: "[:\\-]", options: .regularExpression) {
            clean = String(clean[..<range.lowerBound])
        }
        return clean.trimmingCharacters(in: .whitespaces)
    }
    
    private func isStrictMatch(root: String, candidate: String) -> Bool {
        let r = root.lowercased()
        let c = candidate.lowercased()
        guard c.hasPrefix(r) else { return false }
        if c == r { return true }
        
        let index = c.index(c.startIndex, offsetBy: r.count)
        let nextChar = c[index]
        let allowedSeparators = CharacterSet(charactersIn: " :-").union(CharacterSet.decimalDigits)
        return nextChar.unicodeScalars.allSatisfy { allowedSeparators.contains($0) }
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
}
