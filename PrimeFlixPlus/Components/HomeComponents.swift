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

// MARK: - Continue Watching Card (Enhanced)
struct ContinueWatchingCard: View {
    let channel: Channel
    let onClick: () -> Void
    
    @FocusState private var isFocused: Bool
    @FetchRequest var progressHistory: FetchedResults<WatchProgress>
    
    init(channel: Channel, onClick: @escaping () -> Void) {
        self.channel = channel
        self.onClick = onClick
        
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
    
    // Smart Title Logic: Prefer Episode Name if available
    var displayTitle: String {
        if let epName = channel.episodeName {
            return epName
        }
        return channel.title
    }
    
    var displaySubtitle: String {
        if channel.season > 0 {
            return "S\(channel.season) E\(channel.episode)"
        }
        return ""
    }
    
    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .bottom) {
                // 1. Thumbnail (Prefer Backdrop for episodes if available)
                AsyncImage(url: URL(string: channel.backdrop ?? channel.cover ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        CinemeltTheme.charcoal
                        if let cover = channel.cover {
                            // Fallback to poster in 16:9 container if backdrop missing
                            AsyncImage(url: URL(string: cover)) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Text(String(channel.title.prefix(1)))
                                    .font(CinemeltTheme.fontTitle(50))
                                    .foregroundColor(CinemeltTheme.cream.opacity(0.1))
                            }
                            .blur(radius: 20) // Blur poster to make background
                        }
                    }
                }
                .frame(width: 340, height: 190)
                .clipped()
                
                // 2. Info Overlay (Always visible for CW)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.9)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayTitle)
                            .font(CinemeltTheme.fontBody(22))
                            .fontWeight(.bold)
                            .foregroundColor(isFocused ? .white : CinemeltTheme.cream)
                            .lineLimit(1)
                        
                        if !displaySubtitle.isEmpty {
                            Text(displaySubtitle)
                                .font(CinemeltTheme.fontBody(16))
                                .foregroundColor(CinemeltTheme.accent)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .padding(.bottom, 8)
                
                // 3. Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(height: 6)
                        
                        Rectangle()
                            .fill(CinemeltTheme.accent)
                            .frame(width: geo.size.width * progressPercentage, height: 6)
                            .shadow(color: CinemeltTheme.accent, radius: 4)
                    }
                }
                .frame(height: 6)
            }
        }
        .buttonStyle(CinemeltCardButtonStyle())
        .focused($isFocused)
        .frame(width: 340, height: 190)
        .cornerRadius(16)
    }
}
