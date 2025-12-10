import SwiftUI

struct LiveTVView: View {
    var onPlay: (Channel) -> Void
    var onGuide: () -> Void // Action to open the Full Grid Guide
    
    @StateObject private var viewModel = LiveTVViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    @FocusState private var focusedChannel: String?
    
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
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 40) {
                        
                        // MARK: - Header & Actions
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
                        }
                        .padding(.horizontal, 80)
                        .padding(.top, 40)
                        
                        // MARK: - Special Lanes
                        
                        // 1. Favorites
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
                        
                        // 2. Recently Watched
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
                        
                        // MARK: - All Categories (Lazy Load)
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
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
        }
    }
}

// MARK: - Subcomponents

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
            .padding(.leading, 80)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(channels) { channel in
                        LiveChannelCard(
                            channel: channel,
                            program: viewModel.getProgram(for: channel),
                            progress: viewModel.getProgress(for: viewModel.getProgram(for: channel) ?? Programme()),
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
                .padding(.horizontal, 80)
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
                .padding(.leading, 80)
            
            if let channels = viewModel.channelsByGroup[group] {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 40) {
                        ForEach(channels) { channel in
                            LiveChannelCard(
                                channel: channel,
                                program: viewModel.getProgram(for: channel),
                                progress: viewModel.getProgress(for: viewModel.getProgram(for: channel) ?? Programme()),
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
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                }
                .focusSection()
            } else {
                // Skeleton Loader for row
                ScrollView(.horizontal) {
                    HStack(spacing: 40) {
                        ForEach(0..<5) { _ in
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 280, height: 180)
                        }
                    }
                    .padding(.horizontal, 80)
                }
            }
        }
    }
}

// MARK: - Live Channel Card (EPG Aware)
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
                // 1. Background (Logo)
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
                
                // 2. Info Overlay (Visible on Focus or if Program exists)
                if isFocused || program != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        
                        // Gradient Backing for text readability
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 100)
                        .mask(RoundedRectangle(cornerRadius: 16))
                    }
                }
                
                // 3. Text Content
                VStack(alignment: .leading, spacing: 4) {
                    // Favorite Badge
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
                    
                    // Program Info
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
                            
                            // Time Range
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
                    
                    // Progress Bar
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
            // Focus Border
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isFocused ? CinemeltTheme.accent : Color.clear, lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .shadow(color: isFocused ? CinemeltTheme.accent.opacity(0.4) : .clear, radius: 20)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
        }
        .buttonStyle(.card)
        // Long Press to Toggle Favorite
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
