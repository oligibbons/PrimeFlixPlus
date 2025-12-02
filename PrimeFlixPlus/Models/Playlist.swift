import Foundation
import CoreData

@objc(Playlist)
public class Playlist: NSManagedObject, Identifiable {
    @NSManaged public var title: String
    @NSManaged public var url: String
    @NSManaged public var source: String
    
    // Convenience init
    convenience init(context: NSManagedObjectContext, title: String, url: String, source: DataSourceType) {
        self.init(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Playlist"]!, insertInto: context)
        self.title = title
        self.url = url
        self.source = source.rawValue
    }
}
