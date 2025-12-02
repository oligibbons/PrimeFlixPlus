import SwiftUI

struct MovieCard: View {
    let channel: Channel
    let onClick: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .bottom) {
                
                // 1. Image Layer
                AsyncImage(url: URL(string: channel.cover ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill) // Fill the frame
                    case .failure, .empty:
                        // Fallback
                        ZStack {
                            Color(white: 0.15)
                            Text(String(channel.title.prefix(1)))
                                .font(.system(size: 50, weight: .bold, design: .rounded))
                                .foregroundColor(.gray)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 200, height: 300) // STRICT POSTER SIZE
                .clipped() // Cut off any image overflow
                
                // 2. Gradient Overlay (Readability)
                if isFocused || channel.cover == nil {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.9)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                
                // 3. Text Layer
                if isFocused || channel.cover == nil {
                    Text(channel.title)
                        .font(.caption) // System font is safer for long titles
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .frame(width: 200, height: 300) // Ensure button takes same space
        // Neon Glow Effect
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.cyan : Color.clear, lineWidth: 3)
                .shadow(color: isFocused ? Color.cyan.opacity(0.8) : .clear, radius: 15, x: 0, y: 0)
        )
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
    }
}
