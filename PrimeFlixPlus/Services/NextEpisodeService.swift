import Foundation
import CoreData

/// Service responsible for calculating the "Up Next" logic.
/// Uses a Hybrid Strategy: Checks strict Database relationships first, falls back to Regex/Title parsing.
class NextEpisodeService {
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Public API
    
    func findNextEpisode(currentChannel: Channel) -> Channel? {
        // Strategy A: Strict Metadata Match (Xtream / Structured Data)
        if let seriesId = currentChannel.seriesId, !seriesId.isEmpty, seriesId != "0" {
            // 1. Check next episode in current season
            if let next = findSpecificEpisodeByMetadata(
                playlistUrl: currentChannel.playlistUrl,
                seriesId: seriesId,
                season: Int(currentChannel.season),
                episode: Int(currentChannel.episode) + 1
            ) {
                return next
            }
            
            // 2. Check first episode of next season
            if let nextSeason = findSpecificEpisodeByMetadata(
                playlistUrl: currentChannel.playlistUrl,
                seriesId: seriesId,
                season: Int(currentChannel.season) + 1,
                episode: 1
            ) {
                return nextSeason
            }
        }
        
        // Strategy B: Fallback Title Parsing (M3U / Missing Metadata)
        // If the provider didn't send a series_id, we parse "Show Name S01E01" from the title.
        let raw = currentChannel.title
        let (s, e) = ChannelStruct.parseSeasonEpisode(from: raw)
        
        if s > 0 || e > 0 {
            return findNextByTitle(currentChannel: currentChannel, season: s, episode: e)
        }
        
        return nil
    }
    
    // MARK: - Strategy A: Strict DB Lookup
    
    private func findSpecificEpisodeByMetadata(playlistUrl: String, seriesId: String, season: Int, episode: Int) -> Channel? {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.predicate = NSPredicate(
            format: "playlistUrl == %@ AND seriesId == %@ AND season == %d AND episode == %d",
            playlistUrl, seriesId, season, episode
        )
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }
    
    // MARK: - Strategy B: Fuzzy Title Lookup
    
    private func findNextByTitle(currentChannel: Channel, season: Int, episode: Int) -> Channel? {
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
        
        // Prepare target strings
        let sPadded = String(format: "%02d", season)
        let ePadded = String(format: "%02d", episode)
        
        // Identify the "Show Name" base
        let info = TitleNormalizer.parse(rawTitle: original.title)
        // Use a prefix scan to limit the DB search space before filtering in Swift
        let prefix = String(info.normalizedTitle.prefix(5))
        
        req.predicate = NSPredicate(
            format: "playlistUrl == %@ AND type == 'series' AND title BEGINSWITH[cd] %@",
            original.playlistUrl, prefix
        )
        req.fetchLimit = 100 // Cap to prevent memory explosion on huge lists
        
        guard let candidates = try? context.fetch(req) else { return nil }
        
        // Perform precise matching in memory (Core Data regex is expensive/limited)
        return candidates.first { ch in
            let title = ch.title.uppercased()
            
            // Ensure it's actually the same show (contains normalized title)
            if !ch.title.localizedCaseInsensitiveContains(info.normalizedTitle) { return false }
            
            // Check for standard SxxExx patterns
            // "S01E02" OR "S1E2" OR "1x02"
            return title.contains("S\(sPadded)E\(ePadded)") ||
                   title.contains("S\(season)E\(episode)") ||
                   title.contains("\(season)X\(ePadded)")
        }
    }
}
