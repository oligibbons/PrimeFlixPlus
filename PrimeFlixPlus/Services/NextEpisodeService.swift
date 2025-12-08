import Foundation
import CoreData

/// Service responsible for calculating the "Up Next" logic.
/// Uses a Hybrid Strategy: Checks strict Database relationships first, falls back to Regex/Title parsing.
/// VERSION-AWARE: Prioritizes maintaining the same Language/Quality as the current stream.
class NextEpisodeService {
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Public API
    
    func findNextEpisode(currentChannel: Channel) -> Channel? {
        // 1. Analyze Current Stream to establish "Sticky" preferences
        let currentRaw = currentChannel.canonicalTitle ?? currentChannel.title
        let currentInfo = TitleNormalizer.parse(rawTitle: currentRaw)
        
        // Target: Next Episode in Season
        if let nextEp = findBestMatchForEpisode(
            currentChannel: currentChannel,
            currentInfo: currentInfo,
            targetSeason: Int(currentChannel.season),
            targetEpisode: Int(currentChannel.episode) + 1
        ) {
            return nextEp
        }
        
        // Target: First Episode of Next Season
        if let nextSeasonEp = findBestMatchForEpisode(
            currentChannel: currentChannel,
            currentInfo: currentInfo,
            targetSeason: Int(currentChannel.season) + 1,
            targetEpisode: 1
        ) {
            return nextSeasonEp
        }
        
        return nil
    }
    
    // MARK: - Smart Matching Engine
    
    private func findBestMatchForEpisode(
        currentChannel: Channel,
        currentInfo: ContentInfo,
        targetSeason: Int,
        targetEpisode: Int
    ) -> Channel? {
        
        // A. Fetch All Candidates for this specific episode (SxxExx)
        // We fetch ALL versions (4K, 1080p, French, English) of the target episode
        let candidates = fetchCandidates(
            playlistUrl: currentChannel.playlistUrl,
            seriesId: currentChannel.seriesId,
            showTitle: currentInfo.normalizedTitle,
            season: targetSeason,
            episode: targetEpisode
        )
        
        if candidates.isEmpty { return nil }
        
        // B. Rank Candidates based on "Stickiness" to current stream
        let sorted = candidates.sorted { c1, c2 in
            let info1 = TitleNormalizer.parse(rawTitle: c1.canonicalTitle ?? c1.title)
            let info2 = TitleNormalizer.parse(rawTitle: c2.canonicalTitle ?? c2.title)
            
            // Criteria 1: Language Match (Highest Priority)
            let lang1Match = (info1.language == currentInfo.language)
            let lang2Match = (info2.language == currentInfo.language)
            
            if lang1Match != lang2Match {
                return lang1Match // Prefer the one that matches
            }
            
            // Criteria 2: Exact Quality Match
            let qual1Match = (info1.quality == currentInfo.quality)
            let qual2Match = (info2.quality == currentInfo.quality)
            
            if qual1Match != qual2Match {
                return qual1Match
            }
            
            // Criteria 3: Fallback to Highest Quality Score
            return info1.qualityScore > info2.qualityScore
        }
        
        // Return the best match
        return sorted.first
    }
    
    // MARK: - Database Fetching
    
    private func fetchCandidates(playlistUrl: String, seriesId: String?, showTitle: String, season: Int, episode: Int) -> [Channel] {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        
        // Strategy 1: Strict Metadata (Xtream / Structured)
        if let sid = seriesId, !sid.isEmpty, sid != "0" {
            req.predicate = NSPredicate(
                format: "playlistUrl == %@ AND seriesId == %@ AND season == %d AND episode == %d",
                playlistUrl, sid, season, episode
            )
            if let results = try? context.fetch(req), !results.isEmpty {
                return results
            }
        }
        
        // Strategy 2: Fuzzy Title Matching (M3U / Unstructured)
        // Optimization: Prefix match to limit DB scan
        let prefix = String(showTitle.prefix(4))
        
        req.predicate = NSPredicate(
            format: "playlistUrl == %@ AND type == 'series_episode' AND season == %d AND episode == %d AND title BEGINSWITH[cd] %@",
            playlistUrl, season, episode, prefix
        )
        
        guard let potential = try? context.fetch(req) else { return [] }
        
        // Strict in-memory verification
        return potential.filter { ch in
            let chInfo = TitleNormalizer.parse(rawTitle: ch.canonicalTitle ?? ch.title)
            // Ensure it's actually the same show (e.g. "Severance" != "Severance Special")
            return TitleNormalizer.similarity(between: showTitle, and: chInfo.normalizedTitle) > 0.85
        }
    }
}
