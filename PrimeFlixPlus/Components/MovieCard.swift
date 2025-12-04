import SwiftUI

struct MovieCard: View {
    let channel: Channel
    let onClick: () -> Void
    var onFocus: (() -> Void)? = nil // Optional callback for Void Killer
    
    @FocusState private var isFocused: Bool
    
    // Standard Poster Ratio (2:3) scaled for tvOS Grid
    private let width: CGFloat = 200
    private let height: CGFloat = 300
    
    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .bottom) {
                
                // 1. The Poster Image
                AsyncImage(url: URL(string: channel.cover ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                    case .failure, .empty:
                        // "Cinematic" Fallback
                        ZStack {
                            CinemeltTheme.charcoal
                            
                            // Abstract "Melt" Shape
                            Circle()
                                .fill(CinemeltTheme.accent.opacity(0.2))
                                .blur(radius: 20)
                                .offset(x: -20, y: -40)
                            
                            VStack(spacing: 5) {
                                Image(systemName: "film.stack")
                                    .font(.system(size: 40))
                                    .foregroundColor(CinemeltTheme.accent.opacity(0.5))
                                
                                Text(String(channel.title.prefix(1)))
                                    .font(CinemeltTheme.fontTitle(60))
                                    .foregroundColor(CinemeltTheme.cream.opacity(0.1))
                            }
                        }
                    @unknown default:
                        CinemeltTheme.charcoal
                    }
                }
                
                // 2. The "Smoked Glass" Gradient Overlay (Visible on Focus)
                if isFocused {
                    LinearGradient(
                        colors: [.clear, CinemeltTheme.coffee.opacity(0.95)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.title)
                            .font(CinemeltTheme.fontTitle(22))
                            .foregroundColor(CinemeltTheme.cream)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black, radius: 2, x: 0, y: 1)
                        
                        if let quality = channel.quality {
                            Text(quality)
                                .font(CinemeltTheme.fontBody(14))
                                .foregroundColor(CinemeltTheme.accent)
                                .fontWeight(.bold)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
            }
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .frame(width: width, height: height)
        .background(CinemeltTheme.coffee)
        .cornerRadius(16)
        // MARK: - THE AMBILIGHT GLOW
        .shadow(
            color: isFocused ? CinemeltTheme.accent.opacity(0.5) : .black.opacity(0.5),
            radius: isFocused ? 30 : 5,
            x: 0,
            y: isFocused ? 15 : 2
        )
        // Additional "Hard" glow
        .shadow(
            color: isFocused ? CinemeltTheme.accent.opacity(0.3) : .clear,
            radius: 5,
            x: 0,
            y: 0
        )
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isFocused ? 2 : 0
                )
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocus?() }
        }
    }
}
