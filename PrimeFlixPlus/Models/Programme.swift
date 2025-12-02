import Foundation
import CoreData

@objc(Programme)
public class Programme: NSManagedObject, Identifiable {
    @NSManaged public var id: String
    @NSManaged public var channelId: String
    @NSManaged public var title: String
    @NSManaged public var desc: String?
    @NSManaged public var icon: String?
    @NSManaged public var start: Date
    @NSManaged public var end: Date
    @NSManaged public var playlistUrl: String
    
    convenience init(
        context: NSManagedObjectContext,
        channelId: String,
        title: String,
        desc: String? = nil,
        icon: String? = nil,
        start: Date,
        end: Date,
        playlistUrl: String
    ) {
        self.init(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Programme"]!, insertInto: context)
        self.id = "\(channelId)_\(Int(start.timeIntervalSince1970))"
        self.channelId = channelId
        self.title = title
        self.desc = desc
        self.icon = icon
        self.start = start
        self.end = end
        self.playlistUrl = playlistUrl
    }
    
    var isLiveNow: Bool {
        let now = Date()
        return now >= start && now < end
    }
}
