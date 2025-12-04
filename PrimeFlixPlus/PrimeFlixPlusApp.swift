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
                // 1. Main App Content (Sidebar + Views)
                ContentView()
                    .environmentObject(repository)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                
                // 2. Global Sync Overlay
                // Sits on top of everything (Z-Index)
                SyncStatusOverlay()
                    .environmentObject(repository)
                    .zIndex(100)
            }
            .onAppear {
                // 3. Auto-Sync on App Launch
                Task {
                    // Slight delay to allow UI to settle before hammering network
                    try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
                    await repository.syncAll()
                }
            }
        }
    }
}
