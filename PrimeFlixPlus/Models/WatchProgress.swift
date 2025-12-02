import Foundation
import CoreData

@objc(WatchProgress)
public class WatchProgress: NSManagedObject, Identifiable {
    @NSManaged public var channelUrl: String
    @NSManaged public var position: Int64
    @NSManaged public var duration: Int64
    @NSManaged public var lastPlayed: Date
    
    convenience init(context: NSManagedObjectContext, channelUrl: String, position: Int64, duration: Int64) {
        self.init(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["WatchProgress"]!, insertInto: context)
        self.channelUrl = channelUrl
        self.position = position
        self.duration = duration
        self.lastPlayed = Date()
    }
}
