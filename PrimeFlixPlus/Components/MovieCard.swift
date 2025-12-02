import SwiftUI

struct MovieCard: View {
    let channel: Channel
    let onClick: () -> Unit
    
    // Focus State for tvOS remote interaction
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .bottom) {
                // 1. Background Image
                AsyncImage(url: URL(string: channel.cover ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        // Fallback Placeholder
                        ZStack {
                            Color(white: 0.1) // Dark Grey
                            Text(String(channel.title.prefix(1)))
                                .font(.system(size: 50, weight: .bold, design: .rounded))
                                .foregroundColor(.gray)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 2. Title Overlay (Visible on Focus or if image is missing)
                if isFocused || channel.cover == nil {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.9)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    
                    Text(channel.title)
                        .font(.custom("Exo2-Bold", size: 14)) // Fallback to system if font not loaded
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.card) // Native tvOS parallax effect
        .focused($isFocused)
        // Custom Neon Styling on top of the native card
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.cyan : Color.clear, lineWidth: 3)
                .shadow(color: isFocused ? Color.cyan.opacity(0.8) : .clear, radius: 10, x: 0, y: 0)
        )
        .frame(width: 200, height: 300) // Standard Poster Size
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
    }
}

// Typealias to match Kotlin syntax in your mind, though usually Void in Swift
typealias Unit = Void
