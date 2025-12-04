import SwiftUI

@main
struct PrimeFlixPlusApp: App {
    
    // 1. Initialize Core Data Stack
    let persistenceController = PersistenceController.shared
    
    // 2. Initialize Repository (The Brain)
    @StateObject private var repository: PrimeFlixRepository
    
    // 3. Splash Screen State
    @State private var showSplash = true
    
    init() {
        // Initialize repository using the persistent container
        let repo = PrimeFlixRepository(container: PersistenceController.shared.container)
        _repository = StateObject(wrappedValue: repo)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView()
                        .transition(.opacity.animation(.easeOut(duration: 0.8)))
                        .zIndex(2)
                } else {
                    ZStack {
                        // 1. Main App Content
                        ContentView()
                            .environmentObject(repository)
                            .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        
                        // 2. Global Sync Overlay (Toasts)
                        SyncStatusOverlay()
                            .environmentObject(repository)
                            .zIndex(100)
                    }
                    .transition(.opacity.animation(.easeIn(duration: 0.8)))
                    .zIndex(1)
                }
            }
            .onAppear {
                // 4. App Launch Logic
                Task {
                    // Hold splash for 2.5 seconds for branding
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    
                    await MainActor.run {
                        withAnimation {
                            showSplash = false
                        }
                    }
                    
                    // Start background sync
                    await repository.syncAll()
                }
            }
        }
    }
}
