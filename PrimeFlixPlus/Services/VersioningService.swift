import Foundation
import CoreData

/// Service responsible for identifying alternate versions of media.
/// Groups content primarily by Normalized Title to merge disparate Provider IDs.
class VersioningService {
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Public API
    
    /// Finds all channels that represent the same content (Movies or specific Episodes).
    /// Used to find versions like "4K", "1080p", "French", etc. for a single playable item.
    func getVersions(for channel: Channel) -> [Channel] {
        // Always prioritize Title Matching for aggregation.
        // Even if Series IDs differ (Provider Logic), if the normalized title matches, it's the same content.
        return fetchByNormalizedTitle(
            title: channel.title,
            type: channel.type,
            season: Int(channel.season),
            episode: Int(channel.episode)
        )
    }
    
    /// Finds all Episodes for a given Series.
    /// CRITICAL: Matches ALL episodes sharing the same Show Title, regardless of Series ID.
    func getSeriesEcosystem(for channel: Channel) -> [Channel] {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.sortDescriptors = [
            NSSortDescriptor(key: "season", ascending: true),
            NSSortDescriptor(key: "episode", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        
        // Match ANY episode that belongs to a show with this Normalized Title
        req.predicate = NSPredicate(format: "title == %@ AND type == 'series_episode'", channel.title)
        
        let results = (try? context.fetch(req)) ?? []
        return deduplicateByUrl(results)
    }
    
    /// Finds all "Series Containers" (Show-level entries) that match this title.
    /// Used by ViewModel to trigger multi-ID ingestion.
    func findMatchingSeriesContainers(title: String) -> [Channel] {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.predicate = NSPredicate(format: "title == %@ AND type == 'series'", title)
        
        let results = (try? context.fetch(req)) ?? []
        return deduplicateByUrl(results)
    }
    
    // MARK: - Internal Logic
    
    private func fetchByNormalizedTitle(title: String, type: String, season: Int, episode: Int) -> [Channel] {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        
        if type == "series_episode" {
            // Match Show Title + S/E
            // This pulls together S01E01 from "Series ID A" and S01E01 from "Series ID B"
            req.predicate = NSPredicate(
                format: "title == %@ AND season == %d AND episode == %d AND type == 'series_episode'",
                title, season, episode
            )
        } else {
            // Match Movie Title strictly
            req.predicate = NSPredicate(format: "title == %@ AND type == %@", title, type)
        }
        
        // Sort by quality descending so the "Best" one naturally floats to top
        req.sortDescriptors = [NSSortDescriptor(key: "quality", ascending: false)]
        
        return execute(req)
    }
    
    private func execute(_ request: NSFetchRequest<Channel>) -> [Channel] {
        let results = (try? context.fetch(request)) ?? []
        return deduplicateByUrl(results)
    }
    
    private func deduplicateByUrl(_ channels: [Channel]) -> [Channel] {
        var seen = Set<String>()
        return channels.filter {
            if seen.contains($0.url) { return false }
            seen.insert($0.url)
            return true
        }
    }
}
