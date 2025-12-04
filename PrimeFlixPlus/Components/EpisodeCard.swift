import SwiftUI

struct EpisodeCard: View {
    // Linked to your ViewModel
    let episode: DetailsViewModel.MergedEpisode
    
    @Environment(\.isFocused) var isFocused
    
    var body: some View {
        HStack(spacing: 0) {
            
            // 1. Thumbnail with Blend Mask
            ZStack {
                if let url = episode.imageUrl {
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
                    ZStack {
                        CinemeltTheme.charcoal
                        Image(systemName: "play.slash.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.1))
                    }
                }
            }
            .frame(width: 280, height: 160)
            .overlay(
                // Gradient to fade image into the glass background
                LinearGradient(
                    colors: [.clear, CinemeltTheme.charcoal.opacity(0.5)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipped()
            
            // 2. Info Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    // Large "01" styling
                    Text(String(format: "%02d", episode.number))
                        .font(CinemeltTheme.fontTitle(44))
                        .foregroundColor(isFocused ? CinemeltTheme.accent : CinemeltTheme.accent.opacity(0.7))
                        .shadow(color: isFocused ? CinemeltTheme.accent.opacity(0.5) : .clear, radius: 10)
                    
                    Text(episode.title)
                        .font(CinemeltTheme.fontTitle(28))
                        .foregroundColor(isFocused ? .white : CinemeltTheme.cream)
                        .lineLimit(1)
                }
                
                // Divider line
                Rectangle()
                    .fill(Color.white.opacity(isFocused ? 0.3 : 0.1))
                    .frame(height: 1)
                    .padding(.vertical, 4)
                
                Text(episode.overview.isEmpty ? "No details available." : episode.overview)
                    .font(CinemeltTheme.fontBody(20))
                    .foregroundColor(isFocused ? .white.opacity(0.9) : .gray)
                    .lineLimit(3)
                    .lineSpacing(4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            // Glassmorphic backing
            ZStack {
                if isFocused {
                    Color.white.opacity(0.1) // Brighter on focus
                } else {
                    Color.black.opacity(0.2) // Darker at rest
                }
            }
            .background(.ultraThinMaterial)
        )
        .cornerRadius(12)
        // Outer Glow on Focus
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
