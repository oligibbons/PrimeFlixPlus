import SwiftUI

struct MiniDetailsOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    let channel: Channel
    
    // Playback Actions
    var onPlayNext: () -> Void
    var onClose: () -> Void
    
    // Control Actions (New)
    var onShowTracks: () -> Void
    var onShowVersions: () -> Void
    var onShowSettings: () -> Void
    var onToggleFavorite: () -> Void
    
    @FocusState private var focusedButton: String?
    
    // Grid layout for the buttons
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(alignment: .bottom, spacing: 40) {
                
                // 1. Poster / Thumbnail
                if let poster = viewModel.posterImage {
                    AsyncImage(url: poster) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.white.opacity(0.1))
                    }
                    .frame(width: 240, height: 360)
                    .cornerRadius(16)
                    .shadow(radius: 20)
                } else {
                    AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.white.opacity(0.1))
                    }
                    .frame(width: 240, height: 360)
                    .cornerRadius(16)
                }
                
                // 2. Info Block
                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.videoTitle.isEmpty ? channel.title : viewModel.videoTitle)
                        .font(CinemeltTheme.fontTitle(50))
                        .foregroundColor(CinemeltTheme.cream)
                        .lineLimit(2)
                        .shadow(color: .black, radius: 2)
                    
                    // Metadata Row
                    HStack(spacing: 15) {
                        Badge(text: viewModel.qualityBadge)
                        
                        if !viewModel.videoRating.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(CinemeltTheme.accent)
                                    .font(.caption)
                                Text(viewModel.videoRating)
                                    .font(CinemeltTheme.fontBody(22))
                                    .foregroundColor(CinemeltTheme.cream)
                            }
                        }
                        
                        if !viewModel.videoYear.isEmpty {
                            Text(viewModel.videoYear)
                                .font(CinemeltTheme.fontBody(22))
                                .foregroundColor(.gray)
                        }
                        
                        if let dur = viewModel.duration as Double?, dur > 0 {
                            Text("\(Int(dur / 60)) min")
                                .font(CinemeltTheme.fontBody(22))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Text(viewModel.videoOverview.isEmpty ? "No details available." : viewModel.videoOverview)
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                        .lineLimit(4)
                        .lineSpacing(4)
                    
                    Spacer()
                    
                    // Hint
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.up")
                        Text("Swipe Up to Close")
                    }
                    .font(CinemeltTheme.fontBody(18))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 3. Actions & Controls Block
                VStack(alignment: .leading, spacing: 20) {
                    
                    // A. Playback Flow
                    Text("Playback")
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.gray)
                    
                    if viewModel.canPlayNext {
                        Button(action: onPlayNext) {
                            HStack {
                                Image(systemName: "forward.end.fill")
                                VStack(alignment: .leading) {
                                    Text("Next Episode")
                                        .font(CinemeltTheme.fontTitle(24))
                                        .foregroundColor(.black)
                                    if let next = viewModel.nextEpisode {
                                        Text(next.title)
                                            .font(.caption)
                                            .foregroundColor(.black.opacity(0.7))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 15)
                            .background(CinemeltTheme.accent)
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "next")
                    } else {
                        Button(action: { viewModel.restartPlayback() }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Restart")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "restart")
                    }
                    
                    Divider().background(Color.white.opacity(0.2))
                    
                    // B. Options Grid (Settings, Tracks, etc.)
                    Text("Options")
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.gray)
                    
                    LazyVGrid(columns: columns, spacing: 15) {
                        // 1. Audio/Subs
                        Button(action: onShowTracks) {
                            VStack {
                                Image(systemName: "captions.bubble.fill")
                                    .font(.title2)
                                Text("Tracks")
                                    .font(.caption)
                            }
                            .frame(height: 70)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "tracks")
                        
                        // 2. Settings
                        Button(action: onShowSettings) {
                            VStack {
                                Image(systemName: "gearshape.fill")
                                    .font(.title2)
                                Text("Settings")
                                    .font(.caption)
                            }
                            .frame(height: 70)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "settings")
                        
                        // 3. Versions (If available)
                        if !viewModel.alternativeVersions.isEmpty {
                            Button(action: onShowVersions) {
                                VStack {
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .font(.title2)
                                    Text("Versions")
                                        .font(.caption)
                                }
                                .frame(height: 70)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedButton, equals: "versions")
                        }
                        
                        // 4. Favorite
                        Button(action: onToggleFavorite) {
                            VStack {
                                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                    .font(.title2)
                                    .foregroundColor(viewModel.isFavorite ? CinemeltTheme.accent : .white)
                                Text("Favorite")
                                    .font(.caption)
                            }
                            .frame(height: 70)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "favorite")
                    }
                }
                .frame(width: 400) // Fixed width for actions column
            }
            .padding(50)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [CinemeltTheme.charcoal, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        ).opacity(0.9)
                    )
                    .ignoresSafeArea()
            )
            .frame(height: 600) // Increased height to fit new controls
            .cornerRadius(40, corners: [.topLeft, .topRight])
            .shadow(radius: 50)
        }
        .onExitCommand { onClose() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Default focus to primary action
                focusedButton = viewModel.canPlayNext ? "next" : "restart"
            }
        }
    }
}
