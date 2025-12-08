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
        
        // 1. Analyze the input channel using the new Aggressive Normalizer
        let rawSource = channel.canonicalTitle ?? channel.title
        let info = TitleNormalizer.parse(rawTitle: rawSource)
        let targetTitle = info.normalizedTitle.lowercased()
        
        // Optimization: Use a broad prefix search to limit DB hits
        // We assume the first 3 chars of the normalized title are stable.
        guard targetTitle.count >= 2 else { return [channel] }
        let prefix = String(targetTitle.prefix(3))
        
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = 1000
        
        var matches: [Channel] = []
        
        // 2. Logic Split: Series Episodes vs Movies/SeriesContainers
        if channel.type == "series_episode" {
            // --- EPISODE MATCHING ---
            // Matches must have: Same Normalized Title + Same SxxExx
            
            // Try Strict Series ID first (if both have it)
            if let sid = channel.seriesId, !sid.isEmpty, sid != "0" {
                request.predicate = NSPredicate(
                    format: "seriesId == %@ AND season == %d AND episode == %d",
                    sid, channel.season, channel.episode
                )
            } else {
                // Fallback to Fuzzy Title Matching
                // Uses the Aggressive Normalized Title prefix
                request.predicate = NSPredicate(
                    format: "type == 'series_episode' AND season == %d AND episode == %d AND title BEGINSWITH[cd] %@",
                    channel.season, channel.episode, prefix
                )
            }
            
            guard let candidates = try? context.fetch(request) else { return [channel] }
            
            matches = candidates.filter { candidate in
                // Double check Series ID if available to prevent cross-show collisions
                if let s1 = channel.seriesId, let s2 = candidate.seriesId, s1 != "0", s2 != "0", s1 != s2 {
                    return false
                }
                
                let candRaw = candidate.canonicalTitle ?? candidate.title
                let candInfo = TitleNormalizer.parse(rawTitle: candRaw)
                
                // Strict Title Match on the Clean Normalized Title
                // "Severance Fr" -> "Severance" == "Severance"
                return TitleNormalizer.similarity(between: targetTitle, and: candInfo.normalizedTitle.lowercased()) > 0.85
            }
            
        } else {
            // --- MOVIE / SERIES CONTAINER MATCHING ---
            
            request.predicate = NSPredicate(
                format: "type == %@ AND title BEGINSWITH[cd] %@",
                channel.type, prefix
            )
            
            guard let candidates = try? context.fetch(request) else { return [channel] }
            
            matches = candidates.filter { candidate in
                let candRaw = candidate.canonicalTitle ?? candidate.title
                let candInfo = TitleNormalizer.parse(rawTitle: candRaw)
                let candTitle = candInfo.normalizedTitle.lowercased()
                
                // Exact Match (Fast)
                if candTitle == targetTitle { return true }
                
                // Fuzzy Match (Slower but handles "Severance." vs "Severance")
                return TitleNormalizer.similarity(between: targetTitle, and: candTitle) > 0.90
            }
        }
        
        // 3. Deduplicate by unique content URL (keep unique versions)
        let unique = deduplicateVariants(matches)
        
        // Ensure at least the original channel is returned if logic fails
        if unique.isEmpty { return [channel] }
        
        return unique
    }
    
    // MARK: - Private Helpers
    
    /// Deduplicates entries while preserving distinct Versions (Lang/Quality).
    private func deduplicateVariants(_ channels: [Channel]) -> [Channel] {
        var seenUrls = Set<String>()
        var uniqueChannels: [Channel] = []
        
        for ch in channels {
            if !seenUrls.contains(ch.url) {
                uniqueChannels.append(ch)
                seenUrls.insert(ch.url)
            }
        }
        
        return uniqueChannels
    }
}
