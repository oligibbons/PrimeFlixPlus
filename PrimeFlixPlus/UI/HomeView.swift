import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlayChannel: (Channel) -> Void
    var onAddPlaylist: () -> Void
    var onSettings: () -> Void
    var onSearch: () -> Void
    
    // Dynamic Hero Background State
    @State private var heroChannel: Channel?
    
    var body: some View {
        ZStack {
            // 1. Dynamic Background Layer
            HomeBackgroundView(heroChannel: heroChannel)
            
            // 2. Main Content Switcher
            if viewModel.selectedPlaylist == nil {
                HomeProfileSelector(
                    playlists: viewModel.playlists,
                    onSelect: { pl in viewModel.selectPlaylist(pl) },
                    onAdd: onAddPlaylist
                )
                .transition(.opacity)
            } else if let categoryTitle = viewModel.drillDownCategory {
                HomeDrillDownView(
                    title: categoryTitle,
                    channels: viewModel.displayedGridChannels,
                    onClose: { viewModel.closeDrillDown() },
                    onPlay: onPlayChannel,
                    onFocus: { ch in withAnimation { heroChannel = ch } }
                )
                .transition(.move(edge: .trailing))
            } else {
                mainFeed
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.drillDownCategory)
        .onAppear { viewModel.configure(repository: repository) }
    }
    
    // MARK: - Main Feed
    var mainFeed: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                
                HomeHeaderView(title: viewModel.selectedPlaylist?.title ?? "Guest")
                
                HomeFilterBar(
                    selectedTab: viewModel.selectedTab,
                    onSelect: { tab in
                        withAnimation { viewModel.selectTab(tab) }
                    }
                )
                
                if viewModel.isLoading {
                    HomeLoadingState()
                } else {
                    HomeLanesView(
                        sections: viewModel.sections,
                        onOpenCategory: { sec in viewModel.openCategory(sec) },
                        onPlay: onPlayChannel,
                        onFocus: { ch in
                            withAnimation(.easeInOut(duration: 0.5)) { heroChannel = ch }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - SUBVIEWS (Extracted to fix Compiler Timeout)

struct HomeBackgroundView: View {
    let heroChannel: Channel?
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground
            
            if let hero = heroChannel {
                GeometryReader { geo in
                    AsyncImage(url: URL(string: hero.cover ?? "")) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .blur(radius: 80)
                            .opacity(0.5)
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.7)], startPoint: .topTrailing, endPoint: .bottomLeading))
                    } placeholder: { Color.clear }
                }
                .ignoresSafeArea()
                .transition(.opacity.animation(.easeInOut(duration: 0.8)))
                .id(hero.url)
            }
        }
    }
}

struct HomeHeaderView: View {
    let title: String
    
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome Back,")
                    .cinemeltBody()
                    .opacity(0.6)
                Text(title)
                    .cinemeltTitle()
                    .font(CinemeltTheme.fontTitle(60))
                    .cinemeltGlow()
            }
            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 60)
    }
}

struct HomeFilterBar: View {
    let selectedTab: StreamType
    let onSelect: (StreamType) -> Void
    @FocusState private var focusedTab: StreamType?
    
    var body: some View {
        HStack(spacing: 30) {
            tabButton(title: "Movies", type: .movie)
            tabButton(title: "Series", type: .series)
            tabButton(title: "Live TV", type: .live)
        }
        .padding(.horizontal, 60)
        .padding(.top, 20)
        .padding(.bottom, 30)
    }
    
    private func tabButton(title: String, type: StreamType) -> some View {
        Button(action: { onSelect(type) }) {
            Text(title)
                .font(CinemeltTheme.fontTitle(24))
                .foregroundColor(selectedTab == type ? .black : CinemeltTheme.cream)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        if selectedTab == type {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(CinemeltTheme.accent)
                                .shadow(color: CinemeltTheme.accent.opacity(0.6), radius: 15)
                        } else {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(CinemeltTheme.glassSurface)
                        }
                    }
                )
        }
        .buttonStyle(.card)
        .focused($focusedTab, equals: type)
        .scaleEffect(focusedTab == type ? 1.1 : 1.0)
    }
}

struct HomeLoadingState: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 30) {
                ProgressView().tint(CinemeltTheme.accent).scaleEffect(2.0)
                Text("Loading Library...").cinemeltBody()
            }
            Spacer()
        }
        .padding(.top, 100)
    }
}

struct HomeLanesView: View {
    let sections: [HomeSection]
    let onOpenCategory: (HomeSection) -> Void
    let onPlay: (Channel) -> Void
    let onFocus: (Channel) -> Void
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 40) {
            ForEach(sections) { section in
                HomeSectionRow(
                    section: section,
                    onOpen: { onOpenCategory(section) },
                    onPlay: onPlay,
                    onFocus: onFocus
                )
            }
        }
        .padding(.bottom, 100)
    }
}

struct HomeSectionRow: View {
    let section: HomeSection
    let onOpen: () -> Void
    let onPlay: (Channel) -> Void
    let onFocus: (Channel) -> Void
    
    @FocusState private var isHeaderFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: onOpen) {
                HStack(spacing: 15) {
                    Text(section.title)
                        .font(CinemeltTheme.fontTitle(32))
                        .foregroundColor(isHeaderFocused ? CinemeltTheme.accent : CinemeltTheme.cream)
                        .shadow(color: isHeaderFocused ? CinemeltTheme.accent.opacity(0.6) : .clear, radius: 10)
                    
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundColor(CinemeltTheme.accent)
                        .opacity(isHeaderFocused ? 1 : 0)
                        .offset(x: isHeaderFocused ? 5 : 0)
                }
            }
            .buttonStyle(.plain)
            .focused($isHeaderFocused)
            .padding(.horizontal, 60)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 50) {
                    ForEach(section.items) { channel in
                        if case .continueWatching = section.type {
                            ContinueWatchingCard(channel: channel) { onPlay(channel) }
                        } else {
                            MovieCard(
                                channel: channel,
                                onClick: { onPlay(channel) },
                                onFocus: { onFocus(channel) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
        }
    }
}

struct HomeDrillDownView: View {
    let title: String
    let channels: [Channel]
    let onClose: () -> Void
    let onPlay: (Channel) -> Void
    let onFocus: (Channel) -> Void
    
    let gridColumns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 60)]
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            
            VStack(alignment: .leading) {
                HStack {
                    Button(action: onClose) {
                        HStack(spacing: 15) {
                            Image(systemName: "arrow.left")
                            Text(title).font(CinemeltTheme.fontTitle(50)).cinemeltGlow()
                        }
                        .foregroundColor(CinemeltTheme.cream)
                    }
                    .buttonStyle(.plain)
                    .padding(60)
                    Spacer()
                }
                
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 80) {
                        ForEach(channels) { channel in
                            MovieCard(
                                channel: channel,
                                onClick: { onPlay(channel) },
                                onFocus: { onFocus(channel) }
                            )
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 100)
                }
            }
        }
        .onExitCommand { onClose() }
    }
}

struct HomeProfileSelector: View {
    let playlists: [Playlist]
    let onSelect: (Playlist) -> Void
    let onAdd: () -> Void
    
    var body: some View {
        VStack(spacing: 60) {
            Text("Who is watching?").cinemeltTitle()
            HStack(spacing: 80) {
                Button(action: onAdd) {
                    VStack {
                        Image(systemName: "plus").font(.system(size: 60)).padding(.bottom, 10)
                        Text("Add Profile").cinemeltTitle()
                    }
                    .frame(width: 300, height: 300)
                    .cinemeltGlass(radius: 150)
                }
                .buttonStyle(CinemeltCardButtonStyle())
                
                ForEach(playlists) { playlist in
                    Button(action: { onSelect(playlist) }) {
                        VStack {
                            Text(String(playlist.title.prefix(1)).uppercased())
                                .font(CinemeltTheme.fontTitle(100))
                                .foregroundColor(CinemeltTheme.accent)
                            Text(playlist.title).cinemeltTitle()
                        }
                        .frame(width: 300, height: 300)
                        .cinemeltGlass(radius: 150)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                }
            }
        }
    }
}
