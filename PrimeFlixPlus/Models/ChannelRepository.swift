import Foundation
import CoreData

class ChannelRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Basic Fetching
    
    func getChannel(byUrl url: String) -> Channel? {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    func toggleFavorite(channel: Channel) {
        channel.isFavorite.toggle()
        saveContext()
    }
    
    // MARK: - Versioning & Variants
    
    /// Finds ALL variants of a channel (different langs, resolutions, SEASONS) based on the Normalized Title.
    /// This powers the "Hub" concept.
    func getVersions(for channel: Channel) -> [Channel] {
        // 1. Parse the title using the new aggressive Normalizer
        let info = TitleNormalizer.parse(rawTitle: channel.title)
        let targetTitle = info.normalizedTitle.lowercased()
        
        // 2. Fetch all candidates of the same type (Movie/Series)
        // Note: We deliberately DO NOT filter by playlistUrl here.
        // This allows us to aggregate "Breaking Bad" from Provider A and Provider B into one hub.
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "type == %@", channel.type)
        
        guard let candidates = try? context.fetch(request) else { return [channel] }
        
        // 3. Smart Filter: Only keep items that normalize to the exact same title
        let variants = candidates.filter { candidate in
            let candidateInfo = TitleNormalizer.parse(rawTitle: candidate.title)
            return candidateInfo.normalizedTitle.lowercased() == targetTitle
        }
        
        return variants.isEmpty ? [channel] : variants
    }
    
    // MARK: - Smart Browsing (Home Screen Deduplication)
    
    func getBrowsingContent(playlistUrl: String, type: String, group: String) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        
        var predicates = [
            NSPredicate(format: "playlistUrl == %@", playlistUrl),
            NSPredicate(format: "type == %@", type)
        ]
        
        if group != "All" {
            predicates.append(NSPredicate(format: "group == %@", group))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        
        guard let allChannels = try? context.fetch(request) else { return [] }
        
        // --- DEDUPLICATION LOGIC ---
        // Group by Normalized Title -> Pick ONE representative.
        // Using the new TitleNormalizer, "Show S1" and "Show S2" will collide here.
        // We pick the first one we find as the "Poster" for the Home Screen.
        // When clicked, DetailsViewModel will find the others using getVersions().
        
        var uniqueMap = [String: Channel]()
        
        for channel in allChannels {
            let info = TitleNormalizer.parse(rawTitle: channel.title)
            let key = info.normalizedTitle.lowercased()
            
            // If we haven't seen this show yet, add it.
            if uniqueMap[key] == nil {
                uniqueMap[key] = channel
            }
        }
        
        return uniqueMap.values.sorted { $0.title < $1.title }
    }
    
    // MARK: - Standard Lists
    
    func getGroups(playlistUrl: String, type: String) -> [String] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Channel")
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type)
        request.propertiesToFetch = ["group"]
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        
        guard let results = try? context.fetch(request) as? [[String: Any]] else { return [] }
        
        let groups = results.compactMap { $0["group"] as? String }
        return Array(Set(groups)).sorted()
    }
    
    func getRecentAdded(playlistUrl: String, type: String) -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = 100
        
        guard let recent = try? context.fetch(request) else { return [] }
        
        // Deduplicate Recent List
        var uniqueMap = [String: Channel]()
        for channel in recent {
            let key = TitleNormalizer.parse(rawTitle: channel.title).normalizedTitle.lowercased()
            if uniqueMap[key] == nil {
                uniqueMap[key] = channel
            }
        }
        
        let sorted = uniqueMap.values.sorted {
            ($0.addedAt ?? Date.distantPast) > ($1.addedAt ?? Date.distantPast)
        }
        
        return Array(sorted.prefix(20))
    }
    
    func getFavorites() -> [Channel] {
        let request = NSFetchRequest<Channel>(entityName: "Channel")
        request.predicate = NSPredicate(format: "isFavorite == YES")
        return (try? context.fetch(request)) ?? []
    }
    
    private func saveContext() {
        if context.hasChanges {
            try? context.save()
        }
    }
}
