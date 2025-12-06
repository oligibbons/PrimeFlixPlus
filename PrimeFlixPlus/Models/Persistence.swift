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
            
            // NEW: Structured Series Metadata for "Next Episode" Logic
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

        // --- Finalize Model ---
        model.entities = [playlistEntity, channelEntity, progEntity, epgEntity, metaEntity]
        
        // 2. Initialize Container
        container = NSPersistentContainer(name: "PrimeFlixPlus", managedObjectModel: model)
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("Core Data Error: \(error), \(error.userInfo)")
            }
        }
        
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

// Helper extension to make defining properties cleaner
extension NSAttributeDescription {
    convenience init(name: String, type: NSAttributeType) {
        self.init()
        self.name = name
        self.attributeType = type
        self.isOptional = true // Default to optional to avoid crash on missing data
    }
}
