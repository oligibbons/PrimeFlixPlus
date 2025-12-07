import SwiftUI

struct EpisodeCard: View {
    // Linked to the new DetailsViewModel.MergedEpisode struct
    let episode: DetailsViewModel.MergedEpisode
    
    @Environment(\.isFocused) var isFocused
    
    var body: some View {
        HStack(spacing: 0) {
            
            // 1. Thumbnail Area
            ZStack(alignment: .bottomLeading) {
                // Image
                if let url = episode.stillPath {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack {
                            CinemeltTheme.charcoal
                            Image(systemName: "tv.fill")
                                .font(.title)
                                .foregroundColor(CinemeltTheme.accent.opacity(0.2))
                        }
                    }
                } else {
                    // Fallback
                    ZStack {
                        CinemeltTheme.charcoal
                        Image(systemName: "play.slash.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.1))
                    }
                }
                
                // --- OVERLAYS ---
                
                // A. Gradient Shade (Always visible for text readability if needed, but mainly for style)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                
                // B. Progress Bar (If in progress and not finished)
                if episode.progress > 0 && !episode.isWatched {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Track
                            Rectangle()
                                .fill(Color.black.opacity(0.6))
                                .frame(height: 6)
                            
                            // Fill
                            Rectangle()
                                .fill(CinemeltTheme.accent)
                                .frame(width: geo.size.width * episode.progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.bottom, 0) // Align to very bottom
                }
                
                // C. "Watched" Overlay (Dim + Icon)
                if episode.isWatched {
                    ZStack {
                        Color.black.opacity(0.7)
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(CinemeltTheme.accent)
                            .shadow(color: CinemeltTheme.accent.opacity(0.8), radius: 10)
                    }
                }
            }
            .frame(width: 280, height: 160)
            .clipped()
            
            // 2. Metadata Content
            VStack(alignment: .leading, spacing: 6) {
                
                // Row 1: Episode Number & Title
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%02d", episode.number))
                        .font(CinemeltTheme.fontTitle(44))
                        .foregroundColor(isFocused ? CinemeltTheme.accent : CinemeltTheme.accent.opacity(0.7))
                        .shadow(color: isFocused ? CinemeltTheme.accent.opacity(0.5) : .clear, radius: 10)
                    
                    Text(episode.title)
                        .font(CinemeltTheme.fontTitle(28))
                        .foregroundColor(isFocused ? .white : CinemeltTheme.cream)
                        .lineLimit(1)
                }
                
                // Row 2: Divider
                Rectangle()
                    .fill(Color.white.opacity(isFocused ? 0.3 : 0.1))
                    .frame(height: 1)
                    .padding(.vertical, 4)
                
                // Row 3: Overview
                Text(episode.overview.isEmpty ? "No details available." : episode.overview)
                    .font(CinemeltTheme.fontBody(20))
                    .foregroundColor(isFocused ? .white.opacity(0.9) : .gray)
                    .lineLimit(3)
                    .lineSpacing(4)
                
                Spacer()
                
                // Row 4: Versions Tag (Chillio Feature)
                if episode.versions.count > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.caption)
                        Text("\(episode.versions.count) Versions")
                            .font(CinemeltTheme.fontBody(16))
                            .fontWeight(.bold)
                    }
                    .foregroundColor(isFocused ? CinemeltTheme.accent : .gray)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Card Container Styling
        .background(
            ZStack {
                if isFocused {
                    Color.white.opacity(0.1) // Highlight
                } else {
                    Color.black.opacity(0.2) // Default state
                }
            }
            .background(.ultraThinMaterial)
        )
        .cornerRadius(12)
        // Focus Effects
        .shadow(
            color: isFocused ? CinemeltTheme.accent.opacity(0.3) : .clear,
            radius: 20,
            x: 0,
            y: 5
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? CinemeltTheme.accent : Color.white.opacity(0.05),
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}
