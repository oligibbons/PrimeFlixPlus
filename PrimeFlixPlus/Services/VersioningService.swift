import Foundation
import CoreData

/// Service responsible for identifying alternate versions of media.
/// Groups content by Series ID (Strict) or Fuzzy Title Matching (Loose).
class VersioningService {
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    /// Finds all channels that represent the same content, preserving language variants.
    func getVersions(for channel: Channel) -> [Channel] {
        // 1. Series Episode Matching (Strict)
        if channel.type == "series_episode" {
            // A. Try Series ID Match
            if let sid = channel.seriesId, !sid.isEmpty, sid != "0" {
                let request = NSFetchRequest<Channel>(entityName: "Channel")
                request.predicate = NSPredicate(
                    format: "seriesId == %@ AND season == %d AND episode == %d",
                    sid, channel.season, channel.episode
                )
                if let matches = try? context.fetch(request), !matches.isEmpty {
                    return deduplicateChannels(matches)
                }
            }
            
            // B. Fallback: Fuzzy Title Match on SxxExx
            let rawSource = channel.canonicalTitle ?? channel.title
            let info = TitleNormalizer.parse(rawTitle: rawSource)
            let baseTitle = info.normalizedTitle.lowercased()
            
            let prefix = String(baseTitle.prefix(3))
            let request = NSFetchRequest<Channel>(entityName: "Channel")
            request.predicate = NSPredicate(format: "type == 'series_episode' AND title BEGINSWITH[cd] %@", prefix)
            request.fetchLimit = 100
            
            guard let candidates = try? context.fetch(request) else { return [channel] }
            
            let targetSE = (channel.season, channel.episode)
            
            let variants = candidates.filter { candidate in
                if candidate.season != targetSE.0 || candidate.episode != targetSE.1 { return false }
                
                let candRaw = candidate.canonicalTitle ?? candidate.title
                let candInfo = TitleNormalizer.parse(rawTitle: candRaw)
                
                return TitleNormalizer.similarity(between: baseTitle, and: candInfo.normalizedTitle.lowercased()) > 0.8
            }
            return variants.isEmpty ? [channel] : deduplicateChannels(variants)
        }
        
        // 2. Movie / Series Container Matching (Fuzzy)
        let rawSource = channel.canonicalTitle ?? channel.title
        let info = TitleNormalizer.parse(rawTitle: rawSource)
        let targetTitle = info.normalizedTitle.lowercased()
        
        let prefix = String(targetTitle.prefix(1))
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@ AND title BEGINSWITH[cd] %@", channel.type, prefix)
        request.fetchLimit = 500
        
        guard let candidates = try? context.fetch(request) else { return [channel] }
        
        // Filter using Levenshtein Distance
        let variants = candidates.filter { candidate in
            let candRaw = candidate.canonicalTitle ?? candidate.title
            let candInfo = TitleNormalizer.parse(rawTitle: candRaw)
            let candTitle = candInfo.normalizedTitle.lowercased()
            
            if candTitle == targetTitle { return true }
            if candTitle.contains(targetTitle) || targetTitle.contains(candTitle) { return true }
            
            let score = TitleNormalizer.similarity(between: targetTitle, and: candTitle)
            return score > 0.7
        }
        
        return variants.isEmpty ? [channel] : deduplicateChannels(variants)
    }
    
    // MARK: - Private Helpers
    
    private func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var uniqueMap = [String: Channel]()
        uniqueMap.reserveCapacity(channels.count)
        
        for channel in channels {
            let raw = channel.canonicalTitle ?? channel.title
            let info = TitleNormalizer.parse(rawTitle: raw)
            
            // BASE KEY: Normalized Title (e.g. "Iron Man")
            var key = info.normalizedTitle.lowercased()
            
            // ADDITION: Series Metadata
            if channel.type == "series_episode" {
                key += "_s\(channel.season)_e\(channel.episode)"
                if let sid = channel.seriesId { key += "_\(sid)" }
            }
            
            // ADDITION: Language & Quality
            // This ensures "French 1080p" and "English 4K" are unique keys
            let lang = info.language ?? "default"
            let quality = info.quality
            key += "_\(lang)_\(quality)"
            
            // Store unique variant
            if uniqueMap[key] == nil {
                uniqueMap[key] = channel
            }
        }
        return Array(uniqueMap.values)
    }
}
