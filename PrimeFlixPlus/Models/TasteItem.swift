import Foundation
import CoreData

@objc(TasteItem)
public class TasteItem: NSManagedObject, Identifiable {
    @NSManaged public var tmdbId: Int64
    @NSManaged public var title: String?
    @NSManaged public var mediaType: String? // "movie" or "tv"
    @NSManaged public var status: String?    // "watched" or "loved"
    @NSManaged public var createdAt: Date?
    
    // Convenience Init
    convenience init(
        context: NSManagedObjectContext,
        tmdbId: Int,
        title: String,
        mediaType: String,
        status: String
    ) {
        self.init(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["TasteItem"]!, insertInto: context)
        self.tmdbId = Int64(tmdbId)
        self.title = title
        self.mediaType = mediaType
        self.status = status
        self.createdAt = Date()
    }
}
