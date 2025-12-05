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
                        // NUCLEAR FIX: .equatable() prevents the ContentView from redrawing
                        // when 'repository' updates its sync status message.
                        ContentView(repository: repository)
                            .equatable()
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
        let context = persistenceController.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Playlist")
        let hasPlaylists = (try? context.count(for: request)) ?? 0 > 0
        
        let delay = hasPlaylists ? 1.0 : 2.5
        
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            await MainActor.run {
                withAnimation {
                    showSplash = false
                }
            }
            
            if hasPlaylists {
                Task.detached(priority: .background) {
                    await repository.syncAll()
                }
            }
        }
    }
}
