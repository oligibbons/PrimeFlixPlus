import Foundation
import CoreData

/// Service responsible for identifying alternate versions of media.
/// Uses strict Normalized Title matching (from ingestion) and Series IDs to group content.
class VersioningService {
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Public API
    
    /// Finds all channels that represent the same content (Movies or specific Episodes).
    /// Used to find versions like "4K", "1080p", "French", etc. for a single playable item.
    func getVersions(for channel: Channel) -> [Channel] {
        // 1. If we have a strict Series ID, use it (Most accurate for Xtream)
        if let seriesId = channel.seriesId, seriesId != "0", !seriesId.isEmpty {
            // If it's an episode, we match SeriesID + Season + Episode
            if channel.type == "series_episode" {
                return fetchBySeriesId(id: seriesId, season: Int(channel.season), episode: Int(channel.episode))
            }
        }
        
        // 2. Fallback: Normalized Title Matching (M3U / Mixed Sources)
        // Since Channel.title is already normalized during ingestion, we can trust it for grouping.
        // This effectively groups "Zootopia 2" and "Zootopia 2 4K" if they share the normalized title "Zootopia 2".
        return fetchByNormalizedTitle(
            title: channel.title,
            type: channel.type,
            season: Int(channel.season),
            episode: Int(channel.episode)
        )
    }
    
    /// Finds all Episodes for a given Series (by Title or ID).
    /// Used to populate the Season/Episode list in DetailsView.
    func getSeriesEcosystem(for channel: Channel) -> [Channel] {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.sortDescriptors = [
            NSSortDescriptor(key: "season", ascending: true),
            NSSortDescriptor(key: "episode", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        
        // Strategy A: Series ID (Strict)
        if let sid = channel.seriesId, sid != "0", !sid.isEmpty {
            req.predicate = NSPredicate(format: "seriesId == %@ AND type == 'series_episode'", sid)
            if let results = try? context.fetch(req), !results.isEmpty {
                return deduplicateByUrl(results)
            }
        }
        
        // Strategy B: Normalized Title (Loose)
        // We match all "series_episodes" that share the same Show Title
        // e.g. If channel.title is "Severance", fetch all episodes where title is also "Severance"
        // (Note: Ingestion ensures episodes inherit the Show Title as their primary 'title')
        req.predicate = NSPredicate(format: "title == %@ AND type == 'series_episode'", channel.title)
        
        let results = (try? context.fetch(req)) ?? []
        return deduplicateByUrl(results)
    }
    
    // MARK: - Internal Query Logic
    
    private func fetchBySeriesId(id: String, season: Int, episode: Int) -> [Channel] {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.predicate = NSPredicate(
            format: "seriesId == %@ AND season == %d AND episode == %d",
            id, season, episode
        )
        return execute(req)
    }
    
    private func fetchByNormalizedTitle(title: String, type: String, season: Int, episode: Int) -> [Channel] {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        
        if type == "series_episode" {
            // Match Show Title + S/E
            req.predicate = NSPredicate(
                format: "title == %@ AND season == %d AND episode == %d AND type == 'series_episode'",
                title, season, episode
            )
        } else {
            // Match Movie Title strictly
            req.predicate = NSPredicate(format: "title == %@ AND type == %@", title, type)
        }
        
        return execute(req)
    }
    
    private func execute(_ request: NSFetchRequest<Channel>) -> [Channel] {
        // Sort by quality so higher quality items appear first in lists implicitly,
        // though the ViewModel will re-sort based on user preference score later.
        request.sortDescriptors = [NSSortDescriptor(key: "quality", ascending: false)]
        
        let results = (try? context.fetch(request)) ?? []
        return deduplicateByUrl(results)
    }
    
    /// Ensures we don't return the exact same URL twice, while allowing different URLs
    /// (which represent different versions) to pass through.
    private func deduplicateByUrl(_ channels: [Channel]) -> [Channel] {
        var seen = Set<String>()
        return channels.filter {
            if seen.contains($0.url) { return false }
            seen.insert($0.url)
            return true
        }
    }
}
