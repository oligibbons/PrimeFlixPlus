import Foundation
import CoreData

class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Basic Fetching
    
    func getChannel(byUrl url: String) -> Channel? {
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    func toggleFavorite(channel: Channel) {
        channel.isFavorite.toggle()
        saveContext()
    }
    
    // MARK: - Versioning
    
    /// Finds other channels that share the same Canonical Title (e.g. finding 4K vs 1080p versions)
    func getRelatedChannels(channel: Channel) -> [Channel] {
        guard let canonical = channel.canonicalTitle, !canonical.isEmpty else { return [] }
        
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND canonicalTitle == %@ AND type == %@", channel.playlistUrl, canonical, channel.type)
        request.sortDescriptors = [NSSortDescriptor(key: "quality", ascending: true)]
        
        return (try? context.fetch(request)) ?? []
    }
    
    // MARK: - Grouping
    
    func getGroups(playlistUrl: String, type: String) -> [String] {
        // CRITICAL FIX: Use NSFetchRequestResult (Generic), NOT Channel.
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
        
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type)
        request.propertiesToFetch = ["group"]
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        
        guard let results = try? context.fetch(request) as? [[String: Any]] else { return [] }
        
        let groups = results.compactMap { $0["group"] as? String }
        return Array(Set(groups)).sorted()
    }
    
    // MARK: - Smart Matching & Browsing
    
    func getBrowsingContent(playlistUrl: String, type: String, group: String) -> [Channel] {
        // Redirect movies to the smart distinct logic to avoid duplicates in the grid
        if type == "movie" {
            return getDistinctMovies(playlistUrl: playlistUrl, group: group)
        }
        
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        var predicates = [
            NSPredicate(format: "playlistUrl == %@", playlistUrl),
            NSPredicate(format: "type == %@", type)
        ]
        
        if group != "All" {
            predicates.append(NSPredicate(format: "group == %@", group))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        
        return (try? context.fetch(request)) ?? []
    }
    
    func getDistinctMovies(playlistUrl: String, group: String) -> [Channel] {
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        
        var predicates = [
            NSPredicate(format: "playlistUrl == %@", playlistUrl),
            NSPredicate(format: "type == %@", "movie")
        ]
        
        if group != "All" {
            predicates.append(NSPredicate(format: "group == %@", group))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        
        guard let allChannels = try? context.fetch(request) else { return [] }
        
        // Deduplicate in memory
        var uniqueMovies = [String: Channel]()
        for channel in allChannels {
            let key = channel.canonicalTitle ?? channel.title
            if uniqueMovies[key] == nil {
                uniqueMovies[key] = channel
            }
        }
        
        return uniqueMovies.values.sorted { $0.title < $1.title }
    }
    
    func getRecentAdded(playlistUrl: String, type: String) -> [Channel] {
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = 20
        return (try? context.fetch(request)) ?? []
    }
    
    func getFavorites() -> [Channel] {
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        request.predicate = NSPredicate(format: "isFavorite == YES")
        return (try? context.fetch(request)) ?? []
    }
    
    private func saveContext() {
        if context.hasChanges {
            try? context.save()
        }
    }
}

extension Channel {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Channel> {
        return NSFetchRequest<Channel>(entityName: "Channel")
    }
}
