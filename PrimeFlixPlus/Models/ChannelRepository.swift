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
    
    // MARK: - Versioning & Variants
    
    /// Finds ALL variants of a channel (different langs, resolutions)
    func getVersions(for channel: Channel) -> [Channel] {
        // 1. If we have a canonical title (from import time), use it.
        // Otherwise, re-parse on the fly to be safe.
        let rawTitle = channel.title
        let info = TitleNormalizer.parse(rawTitle: rawTitle)
        let targetTitle = info.normalizedTitle
        
        // 2. Fetch all candidates from the same playlist & type
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", channel.playlistUrl, channel.type)
        
        guard let candidates = try? context.fetch(request) else { return [channel] }
        
        // 3. Smart Filter in Memory (Core Data Regex is slow/limited)
        let variants = candidates.filter { candidate in
            // Compare normalized titles
            let candidateInfo = TitleNormalizer.parse(rawTitle: candidate.title)
            return candidateInfo.normalizedTitle.lowercased() == targetTitle.lowercased()
        }
        
        return variants.isEmpty ? [channel] : variants
    }
    
    // MARK: - Smart Browsing
    
    func getBrowsingContent(playlistUrl: String, type: String, group: String) -> [Channel] {
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
        
        guard let allChannels = try? context.fetch(request) else { return [] }
        
        // --- DEDUPLICATION LOGIC ---
        // Group by Normalized Title -> Pick ONE representative
        // (The representative doesn't strictly matter here, but picking the "cleanest" looking one is nice)
        
        var uniqueMap = [String: Channel]()
        
        for channel in allChannels {
            let info = TitleNormalizer.parse(rawTitle: channel.title)
            let key = info.normalizedTitle.lowercased()
            
            if uniqueMap[key] == nil {
                uniqueMap[key] = channel
            }
        }
        
        // Return values sorted by title
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
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        request.predicate = NSPredicate(format: "playlistUrl == %@ AND type == %@", playlistUrl, type)
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchLimit = 100
        
        guard let recent = try? context.fetch(request) else { return [] }
        
        // Deduplicate Recent List too
        var uniqueMap = [String: Channel]()
        for channel in recent {
            let key = TitleNormalizer.parse(rawTitle: channel.title).normalizedTitle
            if uniqueMap[key] == nil { uniqueMap[key] = channel }
        }
        
        return Array(uniqueMap.values.sorted { ($0.addedAt ?? Date.distantPast) > ($1.addedAt ?? Date.distantPast) }.prefix(20))
    }
    
    func getFavorites() -> [Channel] {
        let request: NSFetchRequest<Channel> = Channel.fetchRequest()
        request.predicate = NSPredicate(format: "isFavorite == YES")
        return (try? context.fetch(request)) ?? []
    }
    
    private func saveContext() {
        if context.hasChanges { try? context.save() }
    }
}
