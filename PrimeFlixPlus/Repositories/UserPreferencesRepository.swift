import Foundation
import CoreData
import Combine

/// Manages User Tastes, Moods, and "Loose Mode" Content tracking.
class UserPreferencesRepository: ObservableObject {
    
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    
    init(container: NSPersistentContainer) {
        self.container = container
        self.context = container.viewContext
    }
    
    // MARK: - Profile Management
    
    func getProfile() -> TasteProfile {
        let req = NSFetchRequest<TasteProfile>(entityName: "TasteProfile")
        req.predicate = NSPredicate(format: "id == %@", "user_main")
        req.fetchLimit = 1
        
        if let existing = try? context.fetch(req).first {
            return existing
        } else {
            let newProfile = TasteProfile(context: context)
            newProfile.id = "user_main"
            newProfile.isOnboardingComplete = false
            try? context.save()
            return newProfile
        }
    }
    
    func completeOnboarding(moods: [String], genres: [String]) {
        let profile = getProfile()
        profile.selectedMoods = moods.joined(separator: ",")
        profile.selectedGenres = genres.joined(separator: ",")
        profile.isOnboardingComplete = true
        save()
    }
    
    func resetOnboarding() {
        let profile = getProfile()
        profile.isOnboardingComplete = false
        save()
    }
    
    // MARK: - Taste Items (Watched / Loved / Super Loved)
    
    /// Saves a show/movie as Watched, Loved, or Super Loved.
    func saveTasteItem(tmdbId: Int, title: String, type: String, status: String, posterPath: String? = nil) {
        let req = NSFetchRequest<TasteItem>(entityName: "TasteItem")
        req.predicate = NSPredicate(format: "tmdbId == %d", Int64(tmdbId))
        req.fetchLimit = 1
        
        let item: TasteItem
        if let existing = try? context.fetch(req).first {
            item = existing
        } else {
            item = TasteItem(context: context)
            item.tmdbId = Int64(tmdbId)
            item.createdAt = Date()
        }
        
        item.title = title
        item.mediaType = type
        item.status = status
        if let path = posterPath {
            item.posterPath = path
        }
        
        save()
    }
    
    func getTasteItems(status: String? = nil) -> [TasteItem] {
        let req = NSFetchRequest<TasteItem>(entityName: "TasteItem")
        if let status = status {
            req.predicate = NSPredicate(format: "status == %@", status)
        }
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return (try? context.fetch(req)) ?? []
    }
    
    /// Returns a set of TMDB IDs for items marked as "Watched", "Loved", or "Super Loved".
    /// Used by the "Fresh Content" engine to find sequels.
    func getAllWatchedTmdbIds() -> Set<Int> {
        let req = NSFetchRequest<TasteItem>(entityName: "TasteItem")
        req.predicate = NSPredicate(format: "status IN {'watched', 'loved', 'super_loved'}")
        
        let items = (try? context.fetch(req)) ?? []
        return Set(items.map { Int($0.tmdbId) })
    }
    
    /// Returns a set of TMDB IDs for items explicitly marked as "Loved" or "Super Loved".
    /// Used by the Recommendation engine to find similar shows.
    func getAllLovedTmdbIds() -> Set<Int> {
        let req = NSFetchRequest<TasteItem>(entityName: "TasteItem")
        req.predicate = NSPredicate(format: "status IN {'loved', 'super_loved'}")
        
        let items = (try? context.fetch(req)) ?? []
        return Set(items.map { Int($0.tmdbId) })
    }
    
    func removeTasteItem(tmdbId: Int) {
        let req = NSFetchRequest<TasteItem>(entityName: "TasteItem")
        req.predicate = NSPredicate(format: "tmdbId == %d", Int64(tmdbId))
        
        if let items = try? context.fetch(req) {
            for item in items {
                context.delete(item)
            }
            save()
        }
    }
    
    // MARK: - Helpers
    
    private func save() {
        if context.hasChanges {
            try? context.save()
        }
    }
}
