import SwiftUI

struct LiveTVView: View {
    var onPlay: (Channel) -> Void
    var onGuide: () -> Void
    
    @StateObject private var viewModel = LiveTVViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    @FocusState private var focusedChannel: String?
    @FocusState private var isGuideButtonFocused: Bool
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    CinemeltLoadingIndicator()
                    Text("Loading Channels...")
                        .font(CinemeltTheme.fontBody(22))
                        .foregroundColor(.gray)
                    Spacer()
                }
            } else {
                // FIXED LAYOUT: Header is now pinned above the ScrollView
                VStack(alignment: .leading, spacing: 0) {
                    
                    // MARK: - Pinned Header (Focusable Area 1)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Live TV")
                                .font(CinemeltTheme.fontTitle(60))
                                .foregroundColor(CinemeltTheme.cream)
                                .cinemeltGlow()
                            
                            Text("\(viewModel.allGroups.count) Categories • \(viewModel.channelsByGroup.values.flatMap{$0}.count) Channels")
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Guide Button
                        Button(action: onGuide) {
                            HStack(spacing: 15) {
                                Image(systemName: "rectangle.grid.3x2.fill")
                                Text("TV Guide")
                            }
                            .font(CinemeltTheme.fontTitle(28))
                            .foregroundColor(.black)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                            .background(CinemeltTheme.accent)
                            .cornerRadius(12)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($isGuideButtonFocused)
                    }
                    // Apply explicit horizontal margin to header to match safe padding below
                    .padding(.horizontal, CinemeltTheme.Layout.margin)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                    .focusSection() // Tells tvOS this is a distinct navigation group
                    
                    // MARK: - Scrollable Content (Focusable Area 2)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 40) {
                            
                            // 1. Favorites Lane
                            if !viewModel.favoriteChannels.isEmpty {
                                LiveLane(
                                    title: "Favorites",
                                    icon: "heart.fill",
                                    channels: viewModel.favoriteChannels,
                                    viewModel: viewModel,
                                    onPlay: onPlay,
                                    focusedChannel: _focusedChannel
                                )
                            }
                            
                            // 2. Recently Watched Lane
                            if !viewModel.recentChannels.isEmpty {
                                LiveLane(
                                    title: "Recently Watched",
                                    icon: "clock.arrow.circlepath",
                                    channels: viewModel.recentChannels,
                                    viewModel: viewModel,
                                    onPlay: onPlay,
                                    focusedChannel: _focusedChannel
                                )
                            }
                            
                            // 3. All Categories (Lazy Grid)
                            LazyVStack(alignment: .leading, spacing: 50) {
                                ForEach(viewModel.allGroups, id: \.self) { group in
                                    LiveCategoryRow(
                                        group: group,
                                        viewModel: viewModel,
                                        onPlay: onPlay,
                                        focusedChannel: _focusedChannel
                                    )
                                    .onAppear {
                                        viewModel.onCategoryAppeared(category: group)
                                    }
                                }
                            }
                            .padding(.bottom, 100)
                        }
                        // CRITICAL FIX: Safe Padding applied here
                        .standardSafePadding()
                    }
                    .focusSection() // Tells tvOS the scroll area is distinct from the header
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
        }
    }
}

// MARK: - Subcomponents (Unchanged from previous fix)

struct LiveLane: View {
    let title: String
    let icon: String
    let channels: [Channel]
    @ObservedObject var viewModel: LiveTVViewModel
    var onPlay: (Channel) -> Void
    @FocusState var focusedChannel: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .foregroundColor(CinemeltTheme.accent)
                    .font(.title2)
                Text(title)
                    .font(CinemeltTheme.fontTitle(32))
                    .foregroundColor(CinemeltTheme.cream)
                    .cinemeltGlow()
            }
            .padding(.leading, 10) // Small local padding
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(channels) { channel in
                        LiveChannelCard(
                            channel: channel,
                            program: viewModel.getProgram(for: channel),
                            progress: viewModel.getProgress(for: channel),
                            onPlay: { onPlay(channel) },
                            onFavorite: { viewModel.toggleFavorite(channel) }
                        )
                        .focused($focusedChannel, equals: channel.url)
                        .onChange(of: focusedChannel) { focused in
                            if focused == channel.url {
                                viewModel.onChannelFocused(channel)
                            }
                        }
                    }
                }
                .padding(.horizontal, 40) // Focus bloom space
                .padding(.vertical, 40)
            }
            .focusSection()
        }
    }
}

struct LiveCategoryRow: View {
    let group: String
    @ObservedObject var viewModel: LiveTVViewModel
    var onPlay: (Channel) -> Void
    @FocusState var focusedChannel: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(group)
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
                .padding(.leading, 10)
            
            if let channels = viewModel.channelsByGroup[group] {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 40) {
                        ForEach(channels) { channel in
                            LiveChannelCard(
                                channel: channel,
                                program: viewModel.getProgram(for: channel),
                                progress: viewModel.getProgress(for: channel),
                                onPlay: { onPlay(channel) },
                                onFavorite: { viewModel.toggleFavorite(channel) }
                            )
                            .focused($focusedChannel, equals: channel.url)
                            .onChange(of: focusedChannel) { focused in
                                if focused == channel.url {
                                    viewModel.onChannelFocused(channel)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 40)
                }
                .focusSection()
            } else {
                // Skeleton Loader
                ScrollView(.horizontal) {
                    HStack(spacing: 40) {
                        ForEach(0..<5) { _ in
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 280, height: 180)
                        }
                    }
                    .padding(.horizontal, 40)
                }
            }
        }
    }
}

struct LiveChannelCard: View {
    let channel: Channel
    let program: Programme?
    let progress: Double
    
    var onPlay: () -> Void
    var onFavorite: () -> Void
    
    @Environment(\.isFocused) var isFocused
    
    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .bottom) {
                ZStack {
                    Color.white.opacity(0.05)
                    
                    AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Text(String(channel.title.prefix(1)))
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.1))
                    }
                    .padding(30)
                }
                .frame(width: 280, height: 180)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                
                if isFocused || program != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 100)
                        .mask(RoundedRectangle(cornerRadius: 16))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Spacer()
                        if channel.isFavorite {
                            Image(systemName: "heart.fill")
                                .foregroundColor(CinemeltTheme.accent)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    .padding(10)
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.title)
                            .font(CinemeltTheme.fontBody(20))
                            .fontWeight(.bold)
                            .foregroundColor(isFocused ? .white : CinemeltTheme.cream)
                            .lineLimit(1)
                        
                        if let prog = program {
                            Text(prog.title)
                                .font(CinemeltTheme.fontBody(16))
                                .foregroundColor(CinemeltTheme.accent)
                                .lineLimit(1)
                            
                            Text("\(formatTime(prog.start)) - \(formatTime(prog.end))")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        } else {
                            Text("No Info")
                                .font(CinemeltTheme.fontBody(14))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(12)
                    .padding(.bottom, 6)
                    
                    if progress > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.gray.opacity(0.3))
                                Rectangle().fill(CinemeltTheme.accent)
                                    .frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .frame(width: 280, height: 180)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isFocused ? CinemeltTheme.accent : Color.clear, lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .shadow(color: isFocused ? CinemeltTheme.accent.opacity(0.4) : .clear, radius: 20)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
        }
        .buttonStyle(.card)
        .contextMenu {
            Button(action: onFavorite) {
                Label(channel.isFavorite ? "Unfavorite" : "Favorite", systemImage: channel.isFavorite ? "heart.slash" : "heart")
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
