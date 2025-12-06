import Foundation
import CoreData

@objc(TasteProfile)
public class TasteProfile: NSManagedObject, Identifiable {
    @NSManaged public var id: String
    @NSManaged public var selectedMoods: String?
    @NSManaged public var selectedGenres: String?
    @NSManaged public var isOnboardingComplete: Bool
    
    // Helper to get arrays back from comma-separated strings
    public var moods: [String] {
        return selectedMoods?.components(separatedBy: ",") ?? []
    }
    
    public var genres: [String] {
        return selectedGenres?.components(separatedBy: ",") ?? []
    }
}
