import SwiftUI

struct MovieCard: View {
    let channel: Channel
    let onClick: () -> Void
    
    @FocusState private var isFocused: Bool
    
    // Standard Poster Ratio 2:3
    // A10X can handle high-res, but we limit frame size for grid density
    private let width: CGFloat = 200
    private let height: CGFloat = 300
    
    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .bottom) {
                
                // 1. Poster Image
                AsyncImage(url: URL(string: channel.cover ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        // "Cosy" Fallback
                        ZStack {
                            CinemeltTheme.backgroundStart
                            Image(systemName: "film")
                                .font(.system(size: 50))
                                .foregroundColor(CinemeltTheme.accent.opacity(0.3))
                            
                            Text(String(channel.title.prefix(1)))
                                .font(CinemeltTheme.fontTitle(80))
                                .foregroundColor(CinemeltTheme.cream.opacity(0.1))
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: width, height: height)
                .clipped()
                
                // 2. Focused Overlay (Glass Gradient)
                // Only show text/gradient when focused to keep the UI "Pristine"
                if isFocused {
                    LinearGradient(
                        colors: [.clear, CinemeltTheme.backgroundEnd.opacity(0.9)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.title)
                            .font(CinemeltTheme.fontTitle(20))
                            .foregroundColor(CinemeltTheme.cream)
                            .lineLimit(2)
                            .shadow(color: .black, radius: 2, x: 0, y: 1)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.card) // Native tvOS parallax
        .focused($isFocused)
        .frame(width: width, height: height)
        .cornerRadius(12) // Softer corners
        // The "Cinemelt" Glow
        .shadow(
            color: isFocused ? CinemeltTheme.accent.opacity(0.6) : .black.opacity(0.5),
            radius: isFocused ? 20 : 5,
            x: 0,
            y: isFocused ? 10 : 2
        )
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isFocused)
    }
}
