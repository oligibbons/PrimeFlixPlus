import SwiftUI

struct MovieCard: View {
    let channel: Channel
    let onClick: () -> Void
    var onFocus: (() -> Void)? = nil
    
    @FocusState private var isFocused: Bool
    
    // Standard Poster Ratio (2:3) scaled for tvOS Grid
    private let width: CGFloat = 200
    private let height: CGFloat = 300
    
    var body: some View {
        Button(action: onClick) {
            // FIX: The ZStack (Label) must effectively fill the frame for the Card style to work correctly.
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
            // CRITICAL FIX: Frame MUST be applied to the content inside the Button
            // for the tvOS Card style to size itself correctly before the image loads.
            .frame(width: width, height: height)
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .shadow(
            color: isFocused ? CinemeltTheme.accent.opacity(0.5) : .black.opacity(0.5),
            radius: isFocused ? 30 : 5,
            x: 0,
            y: isFocused ? 15 : 2
        )
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isFocused)
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
        .frame(width: width, height: height)
    }
}
