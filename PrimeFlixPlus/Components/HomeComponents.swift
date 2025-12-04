import SwiftUI
import CoreData

// MARK: - Continue Watching Lane
struct ContinueWatchingLane: View {
    let title: String
    let items: [Channel]
    let onItemClick: (Channel) -> Void
    
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 15) {
                Text(title)
                    .font(CinemeltTheme.fontTitle(32))
                    .foregroundColor(CinemeltTheme.cream)
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
                    .padding(.vertical, 30) // Space for focus expansion
                }
            }
        }
    }
}

// MARK: - Continue Watching Card (Smart)
struct ContinueWatchingCard: View {
    let channel: Channel
    let onClick: () -> Void
    
    @FocusState private var isFocused: Bool
    
    // Fetch the specific progress for this channel URL
    @FetchRequest var progressHistory: FetchedResults<WatchProgress>
    
    init(channel: Channel, onClick: @escaping () -> Void) {
        self.channel = channel
        self.onClick = onClick
        
        // Dynamic fetch request based on channel URL
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
            VStack(spacing: 0) {
                // Image Area
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: URL(string: channel.cover ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack {
                            CinemeltTheme.backgroundStart
                            Text(String(channel.title.prefix(1)))
                                .font(CinemeltTheme.fontTitle(40))
                                .foregroundColor(CinemeltTheme.cream.opacity(0.2))
                        }
                    }
                    .frame(width: 320, height: 180) // 16:9 Aspect Ratio
                    .clipped()
                    
                    // Gradient scrim for text/bar readability
                    LinearGradient(
                        colors: [.black.opacity(0.8), .clear],
                        startPoint: .bottom,
                        endPoint: .center
                    )
                    
                    // Progress Bar Area
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)
                            
                            Rectangle()
                                .fill(CinemeltTheme.accent) // Warm Amber
                                .frame(width: geo.size.width * progressPercentage, height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.bottom, 0)
                }
                
                // Text Area (Visible on Focus)
                if isFocused {
                    HStack {
                        Text(channel.title)
                            .font(CinemeltTheme.fontBody(20))
                            .fontWeight(.semibold)
                            .foregroundColor(CinemeltTheme.cream)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // "Up Next" Badge if progress is 0 (Next Episode)
                        if progressPercentage == 0 && channel.type == "series" {
                            Text("UP NEXT")
                                .font(CinemeltTheme.fontTitle(14))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CinemeltTheme.accent)
                                .cornerRadius(4)
                                .foregroundColor(.black)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CinemeltTheme.backgroundEnd)
                }
            }
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .frame(width: 320)
        .cornerRadius(12)
        // Cinemelt Shadow
        .shadow(
            color: isFocused ? CinemeltTheme.accent.opacity(0.5) : .black.opacity(0.3),
            radius: isFocused ? 20 : 5,
            y: 5
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isFocused)
    }
}
