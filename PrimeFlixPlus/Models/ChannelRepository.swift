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
    
    // MARK: - Grouping
    
    func getGroups(playlistUrl: String, type: String) -> [String] {
        // CRITICAL FIX: Use NSFetchRequestResult (Generic), NOT Channel.
        // When .dictionaryResultType is used, Core Data returns [String: Any], not [Channel].
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
        
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type)
        request.propertiesToFetch = ["group"]
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true // Let Database handle deduplication
        
        // Safely cast to Array of Dictionaries
        guard let results = try? context.fetch(request) as? [[String: Any]] else { return [] }
        
        let groups = results.compactMap { $0["group"] as? String }
        return Array(Set(groups)).sorted()
    }
    
    // MARK: - Smart Matching & Browsing
    
    /// Standard fetch for browsing channels, with optional grouping
    func getBrowsingContent(playlistUrl: String, type: String, group: String) -> [Channel] {
        // Redirect movies to the smart distinct logic
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
