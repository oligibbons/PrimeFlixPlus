import SwiftUI
import CoreData

struct SplashView: View {
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // Internal Routing State
    @State private var isActive: Bool = false
    @State private var showSmartLoading: Bool = false
    
    // Animation States
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var glowOpacity: Double = 0.4
    
    var body: some View {
        ZStack {
            if isActive {
                // Logic to switch views once splash is done
                if repository.getAllPlaylists().isEmpty {
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
                // MARK: - Animated Splash Screen
                ZStack {
                    // 1. Background
                    CinemeltTheme.mainBackground.ignoresSafeArea()
                    
                    VStack(spacing: 40) {
                        // 2. Animated Logo
                        ZStack {
                            // Outer Glow Pulse
                            Image("CinemeltLogo")
                                .resizable()
                                .renderingMode(.template)
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(CinemeltTheme.accent)
                                .frame(width: 420)
                                .blur(radius: 40)
                                .opacity(glowOpacity)
                            
                            // Main Logo
                            Image("CinemeltLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 400)
                                .cinemeltGlow()
                        }
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        
                        // 3. Welcome Text (REBRANDED)
                        VStack(spacing: 15) {
                            Text("Cinemelt")
                                .font(CinemeltTheme.fontTitle(80)) // Increased size
                                .foregroundColor(CinemeltTheme.cream)
                                .shadow(color: CinemeltTheme.accent.opacity(0.5), radius: 10, x: 0, y: 5)
                            
                            Text("The Ultimate Streaming Experience")
                                .font(CinemeltTheme.fontBody(32)) // Increased size
                                .foregroundColor(CinemeltTheme.cream.opacity(0.6))
                                .tracking(2)
                        }
                        .opacity(textOpacity)
                        .offset(y: textOpacity == 1.0 ? 0 : 20)
                    }
                }
                .drawingGroup()
            }
        }
        .onAppear {
            // 1. Trigger Animations
            startAnimations()
            
            // 2. Kick off the smart sync (Data Pre-loading)
            Task {
                await repository.syncAll(force: false)
            }
            
            // 3. Handle UI Transition to App
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation {
                    self.isActive = true
                }
                checkSyncStatus()
            }
        }
    }
    
    private func startAnimations() {
        // A. Logo Pop
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        
        // B. Text Fade In (Staggered)
        withAnimation(.easeOut(duration: 0.8).delay(0.4)) {
            textOpacity = 1.0
        }
        
        // C. Continuous Glow Pulse
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowOpacity = 0.8
        }
    }
    
    private func checkSyncStatus() {
        // Simple polling to transition from Splash -> SmartLoading -> Home smoothly
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
