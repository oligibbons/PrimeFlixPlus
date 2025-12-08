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
            NSAttributeDescription(name: "title", type: .stringAttributeType), // Normalized Show Title
            NSAttributeDescription(name: "group", type: .stringAttributeType),
            NSAttributeDescription(name: "cover", type: .stringAttributeType), // Poster (2:3)
            NSAttributeDescription(name: "type", type: .stringAttributeType),
            NSAttributeDescription(name: "playlistUrl", type: .stringAttributeType),
            NSAttributeDescription(name: "canonicalTitle", type: .stringAttributeType), // Raw
            NSAttributeDescription(name: "quality", type: .stringAttributeType),
            NSAttributeDescription(name: "addedAt", type: .dateAttributeType),
            NSAttributeDescription(name: "isFavorite", type: .booleanAttributeType),
            
            // Structured Series Metadata
            NSAttributeDescription(name: "seriesId", type: .stringAttributeType),
            NSAttributeDescription(name: "season", type: .integer16AttributeType),
            NSAttributeDescription(name: "episode", type: .integer16AttributeType),
            
            // NEW: Enhanced Metadata Properties
            NSAttributeDescription(name: "episodeName", type: .stringAttributeType), // "Pilot"
            NSAttributeDescription(name: "overview", type: .stringAttributeType),    // Synopsis
            NSAttributeDescription(name: "backdrop", type: .stringAttributeType)     // 16:9 Image
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
        
        // --- Entity: TasteProfile (Onboarding) ---
        let tasteProfileEntity = NSEntityDescription()
        tasteProfileEntity.name = "TasteProfile"
        tasteProfileEntity.managedObjectClassName = "TasteProfile"
        
        tasteProfileEntity.properties = [
            NSAttributeDescription(name: "id", type: .stringAttributeType),
            NSAttributeDescription(name: "selectedMoods", type: .stringAttributeType),
            NSAttributeDescription(name: "selectedGenres", type: .stringAttributeType),
            NSAttributeDescription(name: "isOnboardingComplete", type: .booleanAttributeType)
        ]
        
        // --- Entity: TasteItem (Specific Shows) ---
        let tasteItemEntity = NSEntityDescription()
        tasteItemEntity.name = "TasteItem"
        tasteItemEntity.managedObjectClassName = "TasteItem"
        
        tasteItemEntity.properties = [
            NSAttributeDescription(name: "tmdbId", type: .integer64AttributeType),
            NSAttributeDescription(name: "title", type: .stringAttributeType),
            NSAttributeDescription(name: "mediaType", type: .stringAttributeType),
            NSAttributeDescription(name: "status", type: .stringAttributeType),
            NSAttributeDescription(name: "posterPath", type: .stringAttributeType),
            NSAttributeDescription(name: "createdAt", type: .dateAttributeType)
        ]

        // --- Finalize Model ---
        model.entities = [
            playlistEntity, channelEntity, progEntity, epgEntity, metaEntity,
            tasteProfileEntity, tasteItemEntity
        ]
        
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

// Helper extension
extension NSAttributeDescription {
    convenience init(name: String, type: NSAttributeType) {
        self.init()
        self.name = name
        self.attributeType = type
        self.isOptional = true
    }
}
