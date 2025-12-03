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
                ZStack {
                    AsyncImage(url: URL(string: channel.cover ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(white: 0.1)
                        Text(String(channel.title.prefix(1)))
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 320, height: 180) // 16:9 Aspect Ratio
                .clipped()
                
                // Progress Bar Area
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                    
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.cyan)
                            .frame(width: geo.size.width * progressPercentage)
                    }
                }
                .frame(height: 4)
                
                // Text Area
                HStack {
                    Text(channel.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isFocused ? .white : .gray)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // "Up Next" Badge if progress is 0 (Next Episode)
                    if progressPercentage == 0 && channel.type == "series" {
                        Text("UP NEXT")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(4)
                            .foregroundColor(.cyan)
                    }
                }
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
