import SwiftUI
import CoreData

// MARK: - Continue Watching Lane
struct ContinueWatchingLane: View {
    let title: String
    let items: [Channel]
    let onItemClick: (Channel) -> Void
    
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(CinemeltTheme.fontTitle(32))
                    .foregroundColor(CinemeltTheme.cream)
                    .padding(.leading, 60)
                    .cinemeltGlow()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 50) {
                        ForEach(items) { channel in
                            ContinueWatchingCard(channel: channel) {
                                onItemClick(channel)
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 40)
                }
            }
        }
    }
}

// MARK: - Continue Watching Card (Redesigned)
struct ContinueWatchingCard: View {
    let channel: Channel
    let onClick: () -> Void
    
    @FocusState private var isFocused: Bool
    
    // Fetch the specific progress for this channel URL
    @FetchRequest var progressHistory: FetchedResults<WatchProgress>
    
    init(channel: Channel, onClick: @escaping () -> Void) {
        self.channel = channel
        self.onClick = onClick
        
        // Dynamic fetch request
        _progressHistory = FetchRequest<WatchProgress>(
            entity: WatchProgress.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "channelUrl == %@", channel.url)
        )
    }
    
    var progressPercentage: Double {
        guard let item = progressHistory.first, item.duration > 0 else { return 0 }
        return Double(item.position) / Double(item.duration)
    }
    
    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .bottom) {
                // 1. Thumbnail
                AsyncImage(url: URL(string: channel.cover ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        CinemeltTheme.charcoal
                        Text(String(channel.title.prefix(1)))
                            .font(CinemeltTheme.fontTitle(50))
                            .foregroundColor(CinemeltTheme.cream.opacity(0.1))
                    }
                }
                .frame(width: 340, height: 190)
                .clipped()
                
                // 2. Info Overlay (Visible on Focus)
                if isFocused {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.9)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .transition(.opacity)
                    
                    HStack {
                        Text(channel.title)
                            .font(CinemeltTheme.fontBody(22))
                            .fontWeight(.bold)
                            .foregroundColor(CinemeltTheme.cream)
                            .lineLimit(1)
                            .padding(12)
                        Spacer()
                    }
                }
                
                // 3. Progress Bar (Always visible)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(height: 6)
                        
                        Rectangle()
                            .fill(CinemeltTheme.accent)
                            .frame(width: geo.size.width * progressPercentage, height: 6)
                            .shadow(color: CinemeltTheme.accent, radius: 4) // Glowing bar
                    }
                }
                .frame(height: 6)
            }
        }
        .buttonStyle(CinemeltCardButtonStyle())
        .focused($isFocused)
        .frame(width: 340, height: 190)
        .cornerRadius(16)
        // Ambilight Glow is handled by the ButtonStyle
    }
}
