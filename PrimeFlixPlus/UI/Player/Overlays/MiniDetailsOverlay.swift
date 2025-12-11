import SwiftUI

struct MiniDetailsOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    let channel: Channel
    
    // Playback Actions
    var onPlayNext: () -> Void
    var onClose: () -> Void
    
    // Control Actions
    var onShowTracks: () -> Void
    var onShowVersions: () -> Void
    var onShowSettings: () -> Void
    var onToggleFavorite: () -> Void
    
    @FocusState private var focusedButton: String?
    
    // Settings Access (Direct binding for toggle/size)
    @AppStorage("subtitleScale") var subtitleScale: Double = 1.0
    @AppStorage("areSubtitlesEnabled") var areSubtitlesEnabled: Bool = true
    
    let subtitleSizes: [(String, Double)] = [
        ("S", 0.75), ("M", 1.0), ("L", 1.25), ("XL", 1.5)
    ]
    
    // Grid layout for the main options
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
                    .frame(width: 220, height: 330) // Reduced slightly
                    .cornerRadius(16)
                    .shadow(radius: 20)
                } else {
                    AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.white.opacity(0.1))
                    }
                    .frame(width: 220, height: 330)
                    .cornerRadius(16)
                }
                
                // 2. Info Block
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.videoTitle.isEmpty ? channel.title : viewModel.videoTitle)
                        .font(CinemeltTheme.fontTitle(46)) // Slightly smaller
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
                                    .font(CinemeltTheme.fontBody(20))
                                    .foregroundColor(CinemeltTheme.cream)
                            }
                        }
                        
                        if !viewModel.videoYear.isEmpty {
                            Text(viewModel.videoYear)
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(.gray)
                        }
                        
                        if let dur = viewModel.duration as Double?, dur > 0 {
                            Text("\(Int(dur / 60)) min")
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Text(viewModel.videoOverview.isEmpty ? "No details available." : viewModel.videoOverview)
                        .font(CinemeltTheme.fontBody(22))
                        .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                        .lineLimit(3)
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
                
                // 3. Actions & Controls Block (Right Column)
                VStack(alignment: .leading, spacing: 20) {
                    
                    // A. Playback Flow
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
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(CinemeltTheme.accent)
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "next")
                    } else {
                        Button(action: { viewModel.restartPlayback() }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Restart Episode")
                            }
                            .font(CinemeltTheme.fontBody(20))
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "restart")
                    }
                    
                    Divider().background(Color.white.opacity(0.2))
                    
                    // B. Subtitles (New Section)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subtitles")
                            .font(CinemeltTheme.fontBody(18))
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 10) {
                            // Toggle
                            Button(action: {
                                areSubtitlesEnabled.toggle()
                                viewModel.refreshTracks() // Apply immediately
                            }) {
                                Image(systemName: areSubtitlesEnabled ? "captions.bubble.fill" : "captions.bubble")
                                    .foregroundColor(areSubtitlesEnabled ? .black : .white)
                                    .padding(12)
                                    .background(areSubtitlesEnabled ? CinemeltTheme.accent : Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedButton, equals: "subToggle")
                            
                            // Size Picker
                            ForEach(subtitleSizes, id: \.0) { label, size in
                                Button(action: {
                                    subtitleScale = size
                                    viewModel.refreshTracks() // Reload styles
                                }) {
                                    Text(label)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(subtitleScale == size ? .black : .white)
                                        .frame(width: 40, height: 40)
                                        .background(subtitleScale == size ? CinemeltTheme.white : Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                                .disabled(!areSubtitlesEnabled)
                                .opacity(areSubtitlesEnabled ? 1.0 : 0.3)
                                .focused($focusedButton, equals: "subSize_\(label)")
                            }
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.2))
                    
                    // C. Options Grid
                    LazyVGrid(columns: columns, spacing: 10) {
                        // 1. Audio/Subs (Advanced)
                        Button(action: onShowTracks) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("Sync")
                            }
                            .font(CinemeltTheme.fontBody(18))
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "tracks")
                        
                        // 2. Settings (Quality/Speed)
                        Button(action: onShowSettings) {
                            HStack {
                                Image(systemName: "gearshape.fill")
                                Text("Quality")
                            }
                            .font(CinemeltTheme.fontBody(18))
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "settings")
                        
                        // 3. Versions
                        if !viewModel.alternativeVersions.isEmpty {
                            Button(action: onShowVersions) {
                                HStack {
                                    Image(systemName: "square.stack.3d.up.fill")
                                    Text("Versions")
                                }
                                .font(CinemeltTheme.fontBody(18))
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedButton, equals: "versions")
                        }
                        
                        // 4. Favorite
                        Button(action: onToggleFavorite) {
                            HStack {
                                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                    .foregroundColor(viewModel.isFavorite ? CinemeltTheme.accent : .white)
                                Text("List")
                            }
                            .font(CinemeltTheme.fontBody(18))
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "favorite")
                    }
                }
                .frame(width: 380) // Fixed width for actions column
            }
            .padding(40)
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
            .frame(height: 550) // Reduced total height to fit screen better
            .cornerRadius(40, corners: [.topLeft, .topRight])
            .shadow(radius: 50)
        }
        .onExitCommand { onClose() }
        .onAppear {
            // Delay focus to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if viewModel.canPlayNext {
                    focusedButton = "next"
                } else {
                    focusedButton = "restart"
                }
            }
        }
    }
}
