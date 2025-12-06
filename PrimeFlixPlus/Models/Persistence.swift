import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // 1. Create the Model in Code
        let model = NSManagedObjectModel()
        
        // --- Entity: Playlist ---
        let playlistEntity = NSEntityDescription()
        playlistEntity.name = "Playlist"
        playlistEntity.managedObjectClassName = "Playlist"
        
        playlistEntity.properties = [
            NSAttributeDescription(name: "url", type: .stringAttributeType),
            NSAttributeDescription(name: "title", type: .stringAttributeType),
            NSAttributeDescription(name: "source", type: .stringAttributeType)
        ]
        
        // --- Entity: Channel ---
        let channelEntity = NSEntityDescription()
        channelEntity.name = "Channel"
        channelEntity.managedObjectClassName = "Channel"
        
        channelEntity.properties = [
            NSAttributeDescription(name: "url", type: .stringAttributeType),
            NSAttributeDescription(name: "title", type: .stringAttributeType),
            NSAttributeDescription(name: "group", type: .stringAttributeType),
            NSAttributeDescription(name: "cover", type: .stringAttributeType),
            NSAttributeDescription(name: "type", type: .stringAttributeType),
            NSAttributeDescription(name: "playlistUrl", type: .stringAttributeType),
            NSAttributeDescription(name: "canonicalTitle", type: .stringAttributeType),
            NSAttributeDescription(name: "quality", type: .stringAttributeType),
            NSAttributeDescription(name: "addedAt", type: .dateAttributeType),
            NSAttributeDescription(name: "isFavorite", type: .booleanAttributeType),
            
            // Structured Series Metadata
            NSAttributeDescription(name: "seriesId", type: .stringAttributeType),
            NSAttributeDescription(name: "season", type: .integer16AttributeType),
            NSAttributeDescription(name: "episode", type: .integer16AttributeType)
        ]
        
        // --- Entity: WatchProgress ---
        let progEntity = NSEntityDescription()
        progEntity.name = "WatchProgress"
        progEntity.managedObjectClassName = "WatchProgress"
        
        progEntity.properties = [
            NSAttributeDescription(name: "channelUrl", type: .stringAttributeType),
            NSAttributeDescription(name: "position", type: .integer64AttributeType),
            NSAttributeDescription(name: "duration", type: .integer64AttributeType),
            NSAttributeDescription(name: "lastPlayed", type: .dateAttributeType)
        ]
        
        // --- Entity: Programme (EPG) ---
        let epgEntity = NSEntityDescription()
        epgEntity.name = "Programme"
        epgEntity.managedObjectClassName = "Programme"
        
        epgEntity.properties = [
            NSAttributeDescription(name: "id", type: .stringAttributeType),
            NSAttributeDescription(name: "channelId", type: .stringAttributeType),
            NSAttributeDescription(name: "title", type: .stringAttributeType),
            NSAttributeDescription(name: "desc", type: .stringAttributeType),
            NSAttributeDescription(name: "icon", type: .stringAttributeType),
            NSAttributeDescription(name: "start", type: .dateAttributeType),
            NSAttributeDescription(name: "end", type: .dateAttributeType),
            NSAttributeDescription(name: "playlistUrl", type: .stringAttributeType)
        ]

        // --- Entity: MediaMetadata (TMDB) ---
        let metaEntity = NSEntityDescription()
        metaEntity.name = "MediaMetadata"
        metaEntity.managedObjectClassName = "MediaMetadata"
        
        metaEntity.properties = [
            NSAttributeDescription(name: "tmdbId", type: .integer64AttributeType),
            NSAttributeDescription(name: "mediaType", type: .stringAttributeType),
            NSAttributeDescription(name: "normalizedTitleHash", type: .stringAttributeType),
            NSAttributeDescription(name: "title", type: .stringAttributeType),
            NSAttributeDescription(name: "overview", type: .stringAttributeType),
            NSAttributeDescription(name: "posterPath", type: .stringAttributeType),
            NSAttributeDescription(name: "backdropPath", type: .stringAttributeType),
            NSAttributeDescription(name: "voteAverage", type: .doubleAttributeType),
            NSAttributeDescription(name: "lastUpdated", type: .dateAttributeType)
        ]
        
        // --- NEW Entity: TasteProfile (Onboarding) ---
        // Stores high-level preferences (Moods, Genres)
        let tasteProfileEntity = NSEntityDescription()
        tasteProfileEntity.name = "TasteProfile"
        tasteProfileEntity.managedObjectClassName = "TasteProfile"
        
        tasteProfileEntity.properties = [
            NSAttributeDescription(name: "id", type: .stringAttributeType), // Singleton ID "user_main"
            NSAttributeDescription(name: "selectedMoods", type: .stringAttributeType), // Comma-separated
            NSAttributeDescription(name: "selectedGenres", type: .stringAttributeType), // Comma-separated
            NSAttributeDescription(name: "isOnboardingComplete", type: .booleanAttributeType)
        ]
        
        // --- NEW Entity: TasteItem (Specific Shows) ---
        // Stores specific shows the user has marked as Watched/Loved (Loose Mode)
        let tasteItemEntity = NSEntityDescription()
        tasteItemEntity.name = "TasteItem"
        tasteItemEntity.managedObjectClassName = "TasteItem"
        
        tasteItemEntity.properties = [
            NSAttributeDescription(name: "tmdbId", type: .integer64AttributeType),
            NSAttributeDescription(name: "title", type: .stringAttributeType),
            NSAttributeDescription(name: "mediaType", type: .stringAttributeType), // "movie" or "tv"
            NSAttributeDescription(name: "status", type: .stringAttributeType), // "watched", "loved"
            NSAttributeDescription(name: "createdAt", type: .dateAttributeType)
        ]

        // --- Finalize Model ---
        model.entities = [
            playlistEntity,
            channelEntity,
            progEntity,
            epgEntity,
            metaEntity,
            tasteProfileEntity,
            tasteItemEntity
        ]
        
        // 2. Initialize Container
        container = NSPersistentContainer(name: "PrimeFlixPlus", managedObjectModel: model)
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                // In production, handle migration failures gracefully
                print("Core Data Error: \(error), \(error.userInfo)")
            }
        }
        
        // Handle migration automatically where possible
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

// Helper extension to make defining properties cleaner
extension NSAttributeDescription {
    convenience init(name: String, type: NSAttributeType) {
        self.init()
        self.name = name
        self.attributeType = type
        self.isOptional = true
    }
}

// MARK: - Generated Classes Stub
// Core Data needs classes to map to these entities.
// Since we defined them in code, we must provide the class definitions here or in separate files.

@objc(TasteProfile)
public class TasteProfile: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var selectedMoods: String?
    @NSManaged public var selectedGenres: String?
    @NSManaged public var isOnboardingComplete: Bool
}

@objc(TasteItem)
public class TasteItem: NSManagedObject {
    @NSManaged public var tmdbId: Int64
    @NSManaged public var title: String?
    @NSManaged public var mediaType: String?
    @NSManaged public var status: String?
    @NSManaged public var createdAt: Date?
}
