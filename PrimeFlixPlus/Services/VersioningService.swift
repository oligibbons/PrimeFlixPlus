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
        return fetchByNormalizedTitle(
            title: channel.title,
            type: channel.type,
            season: Int(channel.season),
            episode: Int(channel.episode)
        )
    }
    
    /// Finds all "Series Containers" (Show-level entries) that match this title.
    /// Used by ViewModel to find all versions of a show (EN, FR, 4K, etc.).
    /// Returns: List of Channel objects found in the service's context.
    func findMatchingSeriesContainers(title: String) -> [Channel] {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        // We look for any 'series' (the show folder) that shares the exact same normalized title.
        req.predicate = NSPredicate(format: "title == %@ AND type == 'series'", title)
        
        let results = (try? context.fetch(req)) ?? []
        return deduplicateByUrl(results)
    }
    
    /// Finds all episodes belonging to a specific set of Series IDs.
    /// This allows us to aggregate content from multiple provider entries.
    func getEpisodes(for seriesIds: [String]) -> [Channel] {
        guard !seriesIds.isEmpty else { return [] }
        
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.sortDescriptors = [
            NSSortDescriptor(key: "season", ascending: true),
            NSSortDescriptor(key: "episode", ascending: true)
        ]
        
        // Fetch all episodes where seriesId is in our target list
        req.predicate = NSPredicate(format: "seriesId IN %@ AND type == 'series_episode'", seriesIds)
        
        let results = (try? context.fetch(req)) ?? []
        return deduplicateByUrl(results)
    }
    
    // MARK: - Internal Logic
    
    private func fetchByNormalizedTitle(title: String, type: String, season: Int, episode: Int) -> [Channel] {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        
        if type == "series_episode" {
            req.predicate = NSPredicate(
                format: "title == %@ AND season == %d AND episode == %d AND type == 'series_episode'",
                title, season, episode
            )
        } else {
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
