import Foundation
import CoreData

@objc(Channel)
public class Channel: NSManagedObject, Identifiable {
    @NSManaged public var url: String
    @NSManaged public var playlistUrl: String
    @NSManaged public var title: String
    @NSManaged public var group: String
    @NSManaged public var cover: String?
    @NSManaged public var type: String
    
    // Smart Metadata
    @NSManaged public var canonicalTitle: String?
    @NSManaged public var quality: String?
    @NSManaged public var addedAt: Date?
    @NSManaged public var isFavorite: Bool
    
    // Structured Series Data
    @NSManaged public var seriesId: String?
    @NSManaged public var season: Int16
    @NSManaged public var episode: Int16
    
    // NEW: Enhanced Metadata
    @NSManaged public var episodeName: String? // "The We We Are"
    @NSManaged public var overview: String?    // "Mark begins to question..."
    @NSManaged public var backdrop: String?    // 16:9 Still Image
    
    // Computed helper
    public var id: String { url }
    
    // Convenience init
    convenience init(
        context: NSManagedObjectContext,
        playlistUrl: String,
        url: String,
        title: String,
        group: String,
        cover: String? = nil,
        type: String,
        canonicalTitle: String? = nil,
        quality: String? = nil,
        seriesId: String? = nil,
        season: Int = 0,
        episode: Int = 0,
        episodeName: String? = nil,
        overview: String? = nil,
        backdrop: String? = nil
    ) {
        self.init(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Channel"]!, insertInto: context)
        self.playlistUrl = playlistUrl
        self.url = url
        self.title = title
        self.group = group
        self.cover = cover
        self.type = type
        self.canonicalTitle = canonicalTitle
        self.quality = quality
        self.addedAt = Date()
        self.isFavorite = false
        
        self.seriesId = seriesId
        self.season = Int16(season)
        self.episode = Int16(episode)
        
        self.episodeName = episodeName
        self.overview = overview
        self.backdrop = backdrop
    }
}
