import SwiftUI

// MARK: - Continue Watching Lane
struct ContinueWatchingLane: View {
    let title: String
    let items: [Channel]
    let onItemClick: (Channel) -> Void
    
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 15) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.leading, 50) // Align with grid start
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 40) {
                        ForEach(items) { channel in
                            ContinueWatchingCard(channel: channel) {
                                onItemClick(channel)
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20) // Space for focus expansion
                }
            }
        }
    }
}

// MARK: - Continue Watching Card (Landscape)
struct ContinueWatchingCard: View {
    let channel: Channel
    let onClick: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: onClick) {
            VStack(spacing: 0) {
                // Image Area
                ZStack {
                    AsyncImage(url: URL(string: channel.cover ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(white: 0.1)
                        Text(String(channel.title.prefix(1))).foregroundColor(.gray)
                    }
                }
                .frame(width: 320, height: 180) // 16:9 Aspect Ratio
                .clipped()
                
                // Progress Bar Area
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.gray.opacity(0.3))
                    Rectangle().fill(Color.cyan)
                        .frame(width: 320 * 0.5) // Example: Fixed 50% progress for now
                }
                .frame(height: 4)
                
                // Text Area
                Text(channel.title)
                    .font(.caption)
                    .foregroundColor(isFocused ? .white : .gray)
                    .lineLimit(1)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.15))
            }
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.cyan : Color.clear, lineWidth: 3)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isFocused)
        .frame(width: 320)
    }
}
