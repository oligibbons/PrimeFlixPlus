import SwiftUI

struct ContinueWatchingView: View {
    @EnvironmentObject var repository: PrimeFlixRepository
    @StateObject private var viewModel = ContinueWatchingViewModel()
    
    // Grid Layout: Adaptive to fill screen width efficiently
    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 40)
    ]
    
    var body: some View {
        ZStack {
            // Background
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            if viewModel.isLoading {
                CinemeltLoadingIndicator()
            } else if viewModel.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Header
                        HStack {
                            Image(systemName: "play.tv.fill")
                                .foregroundColor(CinemeltTheme.accent)
                                .font(.title2)
                            Text("Continue Watching")
                                .font(CinemeltTheme.fontTitle(40))
                                .foregroundColor(CinemeltTheme.cream)
                                .cinemeltGlow()
                        }
                        .padding(.horizontal, CinemeltTheme.Layout.margin)
                        .padding(.top, 40)
                        
                        // Grid
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(viewModel.items, id: \.url) { channel in
                                NavigationLink(destination: PlayerView(channel: channel, repository: repository, onBack: {}, onPlayChannel: { _ in })) {
                                    ContinueWatchingCard(channel: channel)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                                // CONTEXT MENU: Long Press to Remove
                                .contextMenu {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            viewModel.removeFromHistory(channel)
                                        }
                                    } label: {
                                        Label("Remove from History", systemImage: "trash")
                                    }
                                    
                                    Button {
                                        repository.toggleFavorite(channel)
                                    } label: {
                                        Label(channel.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: channel.isFavorite ? "heart.slash" : "heart")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, CinemeltTheme.Layout.margin)
                        .padding(.bottom, 60)
                    }
                }
                .focusSection()
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "popcorn")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No unfinished business")
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream.opacity(0.8))
            
            Text("Movies and shows you start (but don't finish)\nwill appear here automatically.")
                .font(CinemeltTheme.fontBody(24))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Internal Card Component
// Specialized card for Continue Watching to show Progress Bar clearly
struct ContinueWatchingCard: View {
    let channel: Channel
    @Environment(\.isFocused) private var isFocused
    
    // We need to fetch the progress specifically for display
    @State private var progress: Double = 0.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Image Area
            ZStack(alignment: .bottomLeading) {
                // Cover
                AsyncImage(url: URL(string: channel.cover ?? "")) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.white.opacity(0.1)
                            Image(systemName: "film")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.2))
                        }
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipped()
                
                // Gradient Overlay
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                
                // Progress Bar (Always Visible here)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 6)
                        
                        Rectangle()
                            .fill(CinemeltTheme.accent)
                            .frame(width: geo.size.width * progress, height: 6)
                            .shadow(color: CinemeltTheme.accent.opacity(0.8), radius: 4)
                    }
                }
                .frame(height: 6)
                .padding(.bottom, 0)
                
                // Play Icon Overlay (On Focus)
                if isFocused {
                    ZStack {
                        Color.black.opacity(0.4)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(CinemeltTheme.cream)
                            .shadow(radius: 10)
                    }
                    .transition(.opacity)
                }
            }
            .cornerRadius(12)
            // Border
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isFocused ? CinemeltTheme.accent : Color.white.opacity(0.1), lineWidth: isFocused ? 3 : 1)
            )
            .shadow(color: isFocused ? CinemeltTheme.accent.opacity(0.3) : .black.opacity(0.3), radius: isFocused ? 15 : 5, x: 0, y: 5)
            
            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.title)
                    .font(CinemeltTheme.fontBody(26))
                    .foregroundColor(isFocused ? .white : .white.opacity(0.8))
                    .lineLimit(1)
                
                // Show "S1 E3" etc if available, else generic info
                if let s = channel.seriesId, !s.isEmpty {
                    Text("S\(channel.season) E\(channel.episode)")
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(CinemeltTheme.accent)
                } else {
                    Text("Resume")
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 8)
        }
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
        .onAppear {
            loadProgress()
        }
    }
    
    private func loadProgress() {
        // Quick fetch from Core Data for UI display
        // In a real app, this might be passed in via ViewModel to avoid view-side fetching,
        // but for a card this is acceptable performance-wise if indexed.
        let context = PersistenceController.shared.container.viewContext
        let req = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        req.predicate = NSPredicate(format: "channelUrl == %@", channel.url)
        req.fetchLimit = 1
        
        if let item = try? context.fetch(req).first {
            let p = Double(item.position)
            let d = Double(item.duration)
            if d > 0 {
                self.progress = p / d
            }
        }
    }
}
