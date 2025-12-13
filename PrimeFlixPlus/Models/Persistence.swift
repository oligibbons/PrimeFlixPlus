import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    // CHANGED: Use standard container for Free Account support
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // 1. Create the Model in Code
        let model = NSManagedObjectModel()
        
        // =====================================================================
        // MARK: - USER DATA (Sync Capable)
        // These entities are separated so they CAN be synced later if you upgrade.
        // =====================================================================
        
        // 1. Playlist
        let playlistEntity = NSEntityDescription()
        playlistEntity.name = "Playlist"
        playlistEntity.managedObjectClassName = "Playlist"
        playlistEntity.configuration = "User" // Was "Cloud"
        
        playlistEntity.properties = [
            NSAttributeDescription(name: "url", type: .stringAttributeType),
            NSAttributeDescription(name: "title", type: .stringAttributeType),
            NSAttributeDescription(name: "source", type: .stringAttributeType)
        ]
        
        // 2. WatchProgress
        let progEntity = NSEntityDescription()
        progEntity.name = "WatchProgress"
        progEntity.managedObjectClassName = "WatchProgress"
        progEntity.configuration = "User"
        
        progEntity.properties = [
            NSAttributeDescription(name: "channelUrl", type: .stringAttributeType),
            NSAttributeDescription(name: "position", type: .integer64AttributeType),
            NSAttributeDescription(name: "duration", type: .integer64AttributeType),
            NSAttributeDescription(name: "lastPlayed", type: .dateAttributeType)
        ]
        
        // 3. TasteProfile
        let tasteProfileEntity = NSEntityDescription()
        tasteProfileEntity.name = "TasteProfile"
        tasteProfileEntity.managedObjectClassName = "TasteProfile"
        tasteProfileEntity.configuration = "User"
        
        tasteProfileEntity.properties = [
            NSAttributeDescription(name: "id", type: .stringAttributeType),
            NSAttributeDescription(name: "selectedMoods", type: .stringAttributeType),
            NSAttributeDescription(name: "selectedGenres", type: .stringAttributeType),
            NSAttributeDescription(name: "isOnboardingComplete", type: .booleanAttributeType)
        ]
        
        // 4. TasteItem
        let tasteItemEntity = NSEntityDescription()
        tasteItemEntity.name = "TasteItem"
        tasteItemEntity.managedObjectClassName = "TasteItem"
        tasteItemEntity.configuration = "User"
        
        tasteItemEntity.properties = [
            NSAttributeDescription(name: "tmdbId", type: .integer64AttributeType),
            NSAttributeDescription(name: "title", type: .stringAttributeType),
            NSAttributeDescription(name: "mediaType", type: .stringAttributeType),
            NSAttributeDescription(name: "status", type: .stringAttributeType),
            NSAttributeDescription(name: "posterPath", type: .stringAttributeType),
            NSAttributeDescription(name: "createdAt", type: .dateAttributeType)
        ]
        
        // =====================================================================
        // MARK: - CACHE DATA (Local Device Only)
        // These are always local to save storage.
        // =====================================================================
        
        // 5. Channel
        let channelEntity = NSEntityDescription()
        channelEntity.name = "Channel"
        channelEntity.managedObjectClassName = "Channel"
        channelEntity.configuration = "Cache" // Was "Local"
        
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
            NSAttributeDescription(name: "inWatchlist", type: .booleanAttributeType),
            
            // Series Metadata
            NSAttributeDescription(name: "seriesId", type: .stringAttributeType),
            NSAttributeDescription(name: "season", type: .integer16AttributeType),
            NSAttributeDescription(name: "episode", type: .integer16AttributeType),
            
            // Enhanced Metadata
            NSAttributeDescription(name: "episodeName", type: .stringAttributeType),
            NSAttributeDescription(name: "overview", type: .stringAttributeType),
            NSAttributeDescription(name: "backdrop", type: .stringAttributeType)
        ]
        
        // 6. Programme (EPG)
        let epgEntity = NSEntityDescription()
        epgEntity.name = "Programme"
        epgEntity.managedObjectClassName = "Programme"
        epgEntity.configuration = "Cache"
        
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

        // 7. MediaMetadata
        let metaEntity = NSEntityDescription()
        metaEntity.name = "MediaMetadata"
        metaEntity.managedObjectClassName = "MediaMetadata"
        metaEntity.configuration = "Cache"
        
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
        model.entities = [
            playlistEntity, channelEntity, progEntity, epgEntity, metaEntity,
            tasteProfileEntity, tasteItemEntity
        ]
        
        // 2. Initialize Container (Standard)
        container = NSPersistentContainer(name: "PrimeFlixPlus", managedObjectModel: model)
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // We still use two separate SQLite files. This is good practice.
            // If you upgrade later, "User.sqlite" can be migrated to CloudKit easily.
            
            let fileManager = FileManager.default
            let appSupportUrl = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? fileManager.createDirectory(at: appSupportUrl, withIntermediateDirectories: true, attributes: nil)
            
            // Store 1: User Data (Future Sync)
            let userStoreUrl = appSupportUrl.appendingPathComponent("User.sqlite")
            let userDesc = NSPersistentStoreDescription(url: userStoreUrl)
            userDesc.configuration = "User"
            
            // Store 2: Cache Data (Local Only)
            let cacheStoreUrl = appSupportUrl.appendingPathComponent("Cache.sqlite")
            let cacheDesc = NSPersistentStoreDescription(url: cacheStoreUrl)
            cacheDesc.configuration = "Cache"
            
            container.persistentStoreDescriptions = [userDesc, cacheDesc]
        }
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Core Data Store Error: \(error), \(error.userInfo)")
            }
        }
        
        // Merge policies are still needed for threading
        container.viewContext.automaticallyMergesChangesFromParent = true
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
