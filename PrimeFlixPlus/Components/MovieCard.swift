import SwiftUI

struct MovieCard: View {
    let channel: Channel
    let onClick: () -> Void
    var onFocus: (() -> Void)? = nil
    
    @FocusState private var isFocused: Bool
    
    // Use standardized dimensions from the Theme
    private let width: CGFloat = CinemeltTheme.Layout.posterWidth
    private let height: CGFloat = CinemeltTheme.Layout.posterHeight
    
    var body: some View {
        Button(action: onClick) {
            // FIX: The ZStack (Label) must effectively fill the frame for the custom style to work.
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
                        fallbackView
                    @unknown default:
                        fallbackView
                    }
                }
                
                // 2. The "Smoked Glass" Gradient Overlay (Visible on Focus)
                if isFocused {
                    LinearGradient(
                        colors: [.clear, CinemeltTheme.coffee.opacity(0.95)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.title)
                            // Increased size for TV readability (was 22)
                            .font(CinemeltTheme.fontTitle(28))
                            .foregroundColor(CinemeltTheme.cream)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black, radius: 2, x: 0, y: 1)
                        
                        if let quality = channel.quality {
                            Text(quality.uppercased())
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(CinemeltTheme.accent)
                                .fontWeight(.bold)
                        }
                    }
                    .padding(16) // Increased padding
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
            }
            // CRITICAL: Explicit frame required for tvOS focus engine to calculate spacing correctly
            .frame(width: width, height: height)
            .background(CinemeltTheme.charcoal)
            .cornerRadius(12) // Slightly sharper corners look better on large screens
            // Border Highlight
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isFocused ? Color.white.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
        }
        // Apply the custom "Lift" physics
        .cinemeltCardStyle()
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocus?() }
        }
    }
    
    // Extracted fallback view for cleaner code and guaranteed sizing
    private var fallbackView: some View {
        ZStack {
            CinemeltTheme.charcoal
            
            Circle()
                .fill(CinemeltTheme.accent.opacity(0.2))
                .blur(radius: 30)
                .offset(x: -20, y: -40)
            
            VStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 50))
                    .foregroundColor(CinemeltTheme.accent.opacity(0.5))
                
                Text(String(channel.title.prefix(1)))
                    .font(CinemeltTheme.fontTitle(80))
                    .foregroundColor(CinemeltTheme.cream.opacity(0.1))
            }
        }
        .frame(width: width, height: height)
    }
}
