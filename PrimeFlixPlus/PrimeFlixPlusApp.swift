import SwiftUI

@main
struct PrimeFlixPlusApp: App {
    
    // 1. Initialize Core Data Stack
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
            ZStack {
                ContentView()
                    // Inject the repository so all Views can access it
                    .environmentObject(repository)
                    // Inject Core Data context
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                
                // 3. Global Notification Overlay
                SyncStatusOverlay()
                    .environmentObject(repository)
            }
            .onAppear {
                // 4. Auto-Sync on App Launch
                Task {
                    // Slight delay to allow UI to settle before hammering network
                    try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
                    await repository.syncAll()
                }
            }
        }
    }
}
