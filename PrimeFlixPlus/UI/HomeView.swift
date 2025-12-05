import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // Updated Actions
    var onPlayChannel: (Channel) -> Void
    var onAddPlaylist: () -> Void
    var onSettings: () -> Void
    var onSearch: (StreamType) -> Void // Now accepts the current tab type
    
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
                
                // Header (Now includes Search & Settings)
                HomeHeaderView(
                    greeting: viewModel.timeGreeting,
                    title: viewModel.witGreeting,
                    onSearch: {
                        // Pass the current active tab to the search view
                        onSearch(viewModel.selectedTab)
                    },
                    onSettings: onSettings
                )
                
                // Tabs
                HomeFilterBar(
                    selectedTab: viewModel.selectedTab,
                    onSelect: { tab in
                        viewModel.selectTab(tab)
                    }
                )
                
                if viewModel.isLoading {
                    HomeLoadingState()
                } else {
                    // Content Lanes
                    HomeLanesView(
                        sections: viewModel.sections,
                        isLoadingMore: viewModel.isLoadingMore,
                        onOpenCategory: { sec in viewModel.openCategory(sec) },
                        onPlay: onPlayChannel,
                        onFocus: { ch in
                            withAnimation(.easeInOut(duration: 0.5)) { heroChannel = ch }
                        },
                        onLoadMore: {
                            viewModel.loadMoreGenres()
                        }
                    )
                }
            }
        }
    }
}

// MARK: - SUBVIEWS

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
    let greeting: String
    let title: String
    var onSearch: () -> Void
    var onSettings: () -> Void
    
    @FocusState private var focusedButton: String?
    
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .cinemeltBody()
                    .font(CinemeltTheme.fontBody(28))
                    .opacity(0.8)
                
                Text(title)
                    .cinemeltTitle()
                    .font(CinemeltTheme.fontTitle(60))
            }
            Spacer()
            
            // Action Buttons
            HStack(spacing: 20) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundColor(focusedButton == "search" ? .black : CinemeltTheme.cream)
                        .padding(15)
                        .background(
                            Circle()
                                .fill(focusedButton == "search" ? CinemeltTheme.accent : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.card)
                .focused($focusedButton, equals: "search")
                
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(focusedButton == "settings" ? .black : CinemeltTheme.cream)
                        .padding(15)
                        .background(
                            Circle()
                                .fill(focusedButton == "settings" ? CinemeltTheme.accent : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.card)
                .focused($focusedButton, equals: "settings")
            }
            .padding(.bottom, 10)
        }
        .padding(.top, 50)
        .padding(.horizontal, 80)
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
        .padding(.horizontal, 80)
        .padding(.top, 30)
        .padding(.bottom, 40)
    }
    
    private func tabButton(title: String, type: StreamType) -> some View {
        Button(action: { onSelect(type) }) {
            Text(title)
                .font(CinemeltTheme.fontTitle(24))
                .foregroundColor(selectedTab == type ? .black : CinemeltTheme.cream)
                .padding(.horizontal, 35)
                .padding(.vertical, 14)
                .background(
                    ZStack {
                        if selectedTab == type {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(CinemeltTheme.accent)
                                .shadow(color: CinemeltTheme.accent.opacity(0.6), radius: 15)
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
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

// ... (Rest of the subviews like HomeLoadingState, HomeLanesView, HomeSectionRow, HomeDrillDownView, HomeProfileSelector remain unchanged)
// For brevity, assuming they are present as provided in previous turns.
// If you need the full file with *every* subview again, let me know, but the key changes were in HomeView and HomeHeaderView above.

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
    let isLoadingMore: Bool
    let onOpenCategory: (HomeSection) -> Void
    let onPlay: (Channel) -> Void
    let onFocus: (Channel) -> Void
    let onLoadMore: () -> Void
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 50) {
            ForEach(sections) { section in
                HomeSectionRow(
                    section: section,
                    onOpen: { onOpenCategory(section) },
                    onPlay: onPlay,
                    onFocus: onFocus
                )
            }
            
            // MARK: - Infinite Scroll Trigger
            Color.clear
                .frame(height: 50)
                .onAppear {
                    onLoadMore()
                }
            
            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(CinemeltTheme.accent)
                        .scaleEffect(1.5)
                    Spacer()
                }
                .padding(.bottom, 50)
            }
        }
        .padding(.bottom, 100)
        .focusSection()
    }
}

struct HomeSectionRow: View {
    let section: HomeSection
    let onOpen: () -> Void
    let onPlay: (Channel) -> Void
    let onFocus: (Channel) -> Void
    
    @FocusState private var isHeaderFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 15) {
                    Text(section.title)
                        .font(CinemeltTheme.fontTitle(36))
                        .foregroundColor(isHeaderFocused ? .black : CinemeltTheme.cream)
                    
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundColor(isHeaderFocused ? .black : CinemeltTheme.accent)
                        .opacity(isHeaderFocused ? 1 : 0)
                        .offset(x: isHeaderFocused ? 5 : 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Color.clear)
            }
            .buttonStyle(.card)
            .focused($isHeaderFocused)
            .padding(.horizontal, 60)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 60) {
                    ForEach(section.items) { channel in
                        ZStack {
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
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
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
    
    let gridColumns = [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 60)]
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            
            VStack(alignment: .leading) {
                HStack {
                    Button(action: onClose) {
                        HStack(spacing: 15) {
                            Image(systemName: "arrow.left")
                            Text(title).font(CinemeltTheme.fontTitle(50))
                        }
                        .foregroundColor(CinemeltTheme.cream)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.card)
                    .padding(80)
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
                    .padding(.horizontal, 80)
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
            Text("Who is watching?")
                .cinemeltTitle()
                .font(CinemeltTheme.fontTitle(60))
            
            HStack(spacing: 80) {
                Button(action: onAdd) {
                    VStack {
                        Image(systemName: "plus")
                            .font(.system(size: 60))
                            .foregroundColor(CinemeltTheme.accent)
                            .padding(.bottom, 10)
                        Text("Add Profile")
                            .font(CinemeltTheme.fontTitle(28))
                            .foregroundColor(CinemeltTheme.cream)
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
