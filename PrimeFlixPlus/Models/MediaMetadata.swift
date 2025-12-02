import Foundation
import CoreData

@objc(MediaMetadata)
public class MediaMetadata: NSManagedObject, Identifiable {
    @NSManaged public var tmdbId: Int64 // Core Data uses Int64 for standard Ints usually
    @NSManaged public var mediaType: String
    @NSManaged public var normalizedTitleHash: String
    @NSManaged public var title: String
    @NSManaged public var overview: String?
    @NSManaged public var posterPath: String?
    @NSManaged public var backdropPath: String?
    @NSManaged public var voteAverage: Double
    @NSManaged public var lastUpdated: Date
    
    convenience init(
        context: NSManagedObjectContext,
        tmdbId: Int,
        title: String,
        normalizedTitleHash: String,
        mediaType: String,
        overview: String? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil
    ) {
        self.init(entity: context.persistentStoreCoordinator!.managedObjectModel.entitiesByName["MediaMetadata"]!, insertInto: context)
        self.tmdbId = Int64(tmdbId)
        self.title = title
        self.normalizedTitleHash = normalizedTitleHash
        self.mediaType = mediaType
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.voteAverage = 0.0
        self.lastUpdated = Date()
    }
}
