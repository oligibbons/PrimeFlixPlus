import SwiftUI
import CoreData

struct SplashView: View {
    // FIX: Replaced direct initialization with EnvironmentObject where appropriate,
    // or kept StateObject if this is the root owner.
    // Given PrimeFlixPlusApp creates the repo, we should ideally access it via .environmentObject,
    // but since this view initializes the app state, keeping StateObject here or passing it down is key.
    // Based on App structure, we will use the property wrapper as defined previously but ensure it passes data correctly.
    
    // NOTE: In the main App file, you likely initialize this.
    // For this specific view to work as a switcher:
    @EnvironmentObject var repository: PrimeFlixRepository
    
    @State private var isActive: Bool = false
    @State private var showSmartLoading: Bool = false
    
    var body: some View {
        ZStack {
            if isActive {
                if repository.getAllPlaylists().isEmpty {
                    // FIX: Added missing arguments for repository and callbacks
                    AddPlaylistView(
                        repository: repository,
                        onPlaylistAdded: {
                            // The repository update will trigger a view refresh automatically
                        },
                        onBack: {
                            // No-op for root splash
                        }
                    )
                } else {
                    if showSmartLoading {
                        SmartLoadingView()
                            .transition(.opacity)
                    } else {
                        // FIX: Updated onSearch closure signature
                        HomeView(
                            onPlayChannel: { _ in },
                            onAddPlaylist: {},
                            onSettings: {},
                            onSearch: { _ in }
                        )
                        .transition(.opacity)
                    }
                }
            } else {
                // Logo Splash
                ZStack {
                    CinemeltTheme.mainBackground.ignoresSafeArea()
                    
                    Image("CinemeltLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 400)
                        .cinemeltGlow()
                }
            }
        }
        .onAppear {
            // 1. Kick off the smart sync
            Task {
                await repository.syncAll(force: false)
            }
            
            // 2. Handle UI Transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    self.isActive = true
                }
                checkSyncStatus()
            }
        }
    }
    
    private func checkSyncStatus() {
        // FIX: Replaced 'timer in' with '_' to silence warning
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if repository.isInitialSync {
                withAnimation { self.showSmartLoading = true }
            } else {
                if self.showSmartLoading {
                    withAnimation(.easeOut(duration: 1.0)) {
                        self.showSmartLoading = false
                    }
                }
                
                if !repository.isSyncing {
                    timer.invalidate()
                }
            }
        }
    }
}
