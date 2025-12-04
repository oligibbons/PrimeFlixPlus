import SwiftUI
import CoreData

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
                        .transition(.opacity.animation(.easeOut(duration: 0.5)))
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
                    .transition(.opacity.animation(.easeIn(duration: 0.5)))
                    .zIndex(1)
                }
            }
            .onAppear {
                handleLaunch()
            }
        }
    }
    
    private func handleLaunch() {
        // 1. Determine if we have existing content to show
        let context = persistenceController.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Playlist")
        let hasPlaylists = (try? context.count(for: request)) ?? 0 > 0
        
        // 2. If we have content, dismiss splash quickly. If fresh install, hold slightly longer for branding.
        let delay = hasPlaylists ? 1.0 : 2.5
        
        Task {
            // Wait for branding
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            await MainActor.run {
                withAnimation {
                    showSplash = false
                }
            }
            
            // 3. Trigger Background Sync (Fire and Forget)
            // This runs in background priority and won't block the Main Thread or UI transitions
            if hasPlaylists {
                Task.detached(priority: .background) {
                    await repository.syncAll()
                }
            }
        }
    }
}
