import SwiftUI

struct SmartLoadingView: View {
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // Animation State
    @State private var pulse: Bool = false
    @State private var rotation: Double = 0
    
    // Dynamic messages based on sync stage
    private var friendlyMessage: String {
        if repository.isInitialSync {
            return "Building your cinema..."
        } else {
            return "Checking for new releases..."
        }
    }
    
    private var detailedStatus: String {
        if let msg = repository.syncStatusMessage {
            return msg
        }
        return repository.syncStats.currentStage
    }
    
    var body: some View {
        ZStack {
            // 1. Background
            CinemeltTheme.mainBackground
                .ignoresSafeArea()
            
            // 2. Content
            VStack(spacing: 40) {
                
                // --- Animation Block ---
                ZStack {
                    // Outer Glow
                    Circle()
                        .stroke(CinemeltTheme.accent.opacity(0.3), lineWidth: 4)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.2 : 1.0)
                        .opacity(pulse ? 0.0 : 1.0)
                    
                    // Inner Spinner
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [CinemeltTheme.accent, CinemeltTheme.coffee]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(Angle(degrees: rotation))
                    
                    // Icon
                    Image(systemName: "film.fill")
                        .font(.system(size: 30))
                        .foregroundColor(CinemeltTheme.cream)
                }
                .padding(.bottom, 20)
                
                // --- Text Block ---
                VStack(spacing: 10) {
                    Text(friendlyMessage)
                        .font(CinemeltTheme.fontTitle(40))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                    
                    Text(detailedStatus)
                        .font(CinemeltTheme.fontBody(22))
                        .foregroundColor(.gray)
                }
                
                // --- Live Stats Grid ---
                if repository.isInitialSync || repository.syncStats.totalItems > 0 {
                    HStack(spacing: 40) {
                        StatPill(icon: "tv", label: "Channels", count: repository.syncStats.liveChannelsAdded)
                        StatPill(icon: "film", label: "Movies", count: repository.syncStats.moviesAdded)
                        StatPill(icon: "play.tv", label: "Series", count: repository.syncStats.seriesAdded)
                    }
                    .padding(30)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    )
                    .transition(.opacity.combined(with: .scale))
                }
                
                // --- Disclaimer ---
                if repository.isInitialSync {
                    Text("Large playlists may take a minute. We're organizing everything for you.")
                        .font(CinemeltTheme.fontBody(16))
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.top, 20)
                }
            }
        }
        .onAppear {
            // Start Animations
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulse = true
            }
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// Helper Component
struct StatPill: View {
    let icon: String
    let label: String
    let count: Int
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(CinemeltTheme.accent)
            
            VStack(alignment: .leading) {
                Text("\(count)")
                    .fontWeight(.bold)
                    .foregroundColor(CinemeltTheme.cream)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(minWidth: 100)
    }
}
