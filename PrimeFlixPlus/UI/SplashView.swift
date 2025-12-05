import SwiftUI

struct SplashView: View {
    @StateObject private var repository = PrimeFlixRepository(container: PersistenceController.shared.container)
    @State private var isActive: Bool = false
    @State private var showSmartLoading: Bool = false
    
    var body: some View {
        ZStack {
            if isActive {
                if repository.getAllPlaylists().isEmpty {
                    AddPlaylistView()
                        .environmentObject(repository)
                } else {
                    if showSmartLoading {
                        SmartLoadingView()
                            .environmentObject(repository)
                            .transition(.opacity)
                    } else {
                        HomeView(
                            onPlayChannel: { _ in }, // Handled internally by HomeView usually
                            onAddPlaylist: {}, // Handled by HomeView state
                            onSettings: {},
                            onSearch: {}
                        )
                        .environmentObject(repository)
                        .transition(.opacity)
                    }
                }
            } else {
                // Logo Splash
                ZStack {
                    CinemeltTheme.mainBackground.ignoresSafeArea()
                    
                    Image("CinemeltLogo") // Ensure this exists in Assets
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 400)
                        .cinemeltGlow()
                }
            }
        }
        .onAppear {
            // 1. Kick off the smart sync immediately
            // This is non-blocking and runs on a background thread
            Task {
                await repository.syncAll(force: false)
            }
            
            // 2. Handle UI Transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    self.isActive = true
                }
                
                // 3. Check if we need the Smart Loading Screen
                checkSyncStatus()
            }
        }
    }
    
    private func checkSyncStatus() {
        // Monitor the repository state
        // If it's an initial huge sync, keep showing the loading screen
        // We check periodically
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            // Access state safely
            if repository.isInitialSync {
                withAnimation { self.showSmartLoading = true }
            } else {
                // Once initial sync is done, or if it was never needed (cached), go to Home
                if self.showSmartLoading {
                    // If we were showing it, fade it out
                    withAnimation(.easeOut(duration: 1.0)) {
                        self.showSmartLoading = false
                    }
                }
                
                // If we aren't syncing anymore, stop checking
                if !repository.isSyncing {
                    timer.invalidate()
                }
            }
        }
    }
}
