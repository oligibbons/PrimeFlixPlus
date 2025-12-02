import SwiftUI

@main
struct PrimeFlixPlusApp: App {
    
    // 1. Initialize Core Data Stack (Code-only version)
    let persistenceController = PersistenceController.shared
    
    // 2. Initialize Repository (The Brain)
    @StateObject private var repository: PrimeFlixRepository
    
    init() {
        // Initialize repository using the persistent container
        let repo = PrimeFlixRepository(container: PersistenceController.shared.container)
        _repository = StateObject(wrappedValue: repo)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject the repository so all Views can access it
                .environmentObject(repository)
                // Inject Core Data context (optional, but good practice for SwiftUI)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
