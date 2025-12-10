import SwiftUI

// MARK: - Scroll Offset Logic
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // Callbacks provided by parent (ContentView)
    // Kept for API compatibility, even if unused in this View now
    var onPlayChannel: (Channel) -> Void
    var onAddPlaylist: () -> Void
    var onSettings: () -> Void
    var onSearch: (StreamType) -> Void
    
    @State private var heroChannel: Channel?
    
    // Navigation & Focus State
    @State private var scrollOffset: CGFloat = 0
    @State private var showEpgGrid: Bool = false
    
    // FOCUS MANAGEMENT (LIFTED)
    @FocusState private var focusedField: HomeFocusField?
    
    enum HomeFocusField: Hashable {
        case tab(StreamType)
        case content // General content focus
    }
    
    var body: some View {
        ZStack {
            // 1. Dynamic Background Layer
            HomeBackgroundView(heroChannel: heroChannel, scrollOffset: scrollOffset)
            
            // 2. Main Content Switcher
            if viewModel.selectedPlaylist == nil {
                HomeProfileSelector(
                    playlists: viewModel.playlists,
                    onSelect: { pl in viewModel.selectPlaylist(pl) },
                    onAdd: onAddPlaylist
                )
                .transition(.opacity)
            } else if showEpgGrid {
                // Full Screen EPG Overlay
                EpgGridView(
                    onPlay: onPlayChannel,
                    onBack: { withAnimation { showEpgGrid = false } }
                )
                .transition(.move(edge: .bottom))
                .zIndex(10)
            } else if let categoryTitle = viewModel.drillDownCategory {
                // Category Drill Down
                HomeDrillDownView(
                    title: categoryTitle,
                    channels: viewModel.displayedGridChannels,
                    onClose: { viewModel.closeDrillDown() },
                    onPlay: onPlayChannel,
                    onFocus: { ch in withAnimation { heroChannel = ch } }
                )
                .transition(.move(edge: .trailing))
            } else {
                // Tab Content
                Group {
                    if viewModel.selectedTab == .live {
                        liveTvInterface
                    } else {
                        mainFeed
                    }
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.drillDownCategory)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showEpgGrid)
        .onAppear {
            viewModel.configure(repository: repository)
            // Default focus to the movie tab on load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if focusedField == nil {
                    focusedField = .tab(.movie)
                }
            }
        }
    }
    
    // MARK: - Live TV Interface
    var liveTvInterface: some View {
        VStack(spacing: 0) {
            // Pinned Filter Bar
            HomeFilterBar(
                selectedTab: viewModel.selectedTab,
                focusedField: _focusedField,
                onSelect: { tab in viewModel.selectTab(tab) }
            )
            .padding(.top, 40)
            .padding(.bottom, 10)
            .background(
                LinearGradient(
                    colors: [CinemeltTheme.charcoal, CinemeltTheme.charcoal.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .zIndex(2)
            
            // The Live Dashboard
            LiveTVView(
                onPlay: onPlayChannel,
                onGuide: { withAnimation { showEpgGrid = true } }
            )
            // MENU BUTTON HANDLER: Return to Tabs
            .onExitCommand {
                withAnimation {
                    focusedField = .tab(viewModel.selectedTab)
                }
            }
        }
    }
    
    // MARK: - Main Feed (Movies/Series)
    var mainFeed: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Scroll Tracker
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geo.frame(in: .named("homeScrollSpace")).minY
                    )
            }
            .frame(height: 0)
            
            VStack(alignment: .leading, spacing: 10) {
                
                // Header (Cleaned up: No icons)
                HomeHeaderView(
                    greeting: viewModel.timeGreeting,
                    title: viewModel.witGreeting
                )
                .focusSection()
                
                // Tabs
                HomeFilterBar(
                    selectedTab: viewModel.selectedTab,
                    focusedField: _focusedField,
                    onSelect: { tab in viewModel.selectTab(tab) }
                )
                .focusSection()
                
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
                        onLoadMore: { viewModel.loadMoreGenres() }
                    )
                    // MENU BUTTON HANDLER: Return to Tabs
                    // We attach it to the content stack so it catches events when deep in the list
                    .onExitCommand {
                        withAnimation {
                            focusedField = .tab(viewModel.selectedTab)
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: "homeScrollSpace")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            self.scrollOffset = value
        }
    }
}

// MARK: - Subviews

struct HomeHeaderView: View {
    let greeting: String
    let title: String
    
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
            
            // Note: Search/Settings buttons removed as they are accessible via Sidebar
        }
        .padding(.top, 50)
        .padding(.horizontal, 80)
    }
}

struct HomeFilterBar: View {
    let selectedTab: StreamType
    @FocusState var focusedField: HomeView.HomeFocusField?
    let onSelect: (StreamType) -> Void
    
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
        // Bind to the parent's focus state so we can force focus here
        .focused($focusedField, equals: .tab(type))
        .scaleEffect(focusedField == .tab(type) ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: focusedField)
    }
}

// MARK: - Passthrough Components (Unchanged logic, just wrappers)

struct HomeBackgroundView: View {
    let heroChannel: Channel?
    var scrollOffset: CGFloat
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground
            if let hero = heroChannel {
                GeometryReader { geo in
                    AsyncImage(url: URL(string: hero.cover ?? "")) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height + 200)
                            .blur(radius: 80)
                            .opacity(0.5)
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.7)], startPoint: .topTrailing, endPoint: .bottomLeading))
                            .offset(y: -scrollOffset * 0.15)
                            .animation(.linear(duration: 0.1), value: scrollOffset)
                    } placeholder: { Color.clear }
                }
                .ignoresSafeArea()
                .transition(.opacity.animation(.easeInOut(duration: 0.8)))
                .id(hero.url)
            }
        }
    }
}

struct HomeLoadingState: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 30) {
                CinemeltLoadingIndicator()
                Text("Loading Library...")
                    .cinemeltBody()
                    .transition(.opacity)
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
            
            Color.clear.frame(height: 50).onAppear { onLoadMore() }
            
            if isLoadingMore {
                HStack { Spacer(); CinemeltLoadingIndicator().scaleEffect(0.8); Spacer() }
                    .padding(.bottom, 50)
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
                                MovieCard(channel: channel, onClick: { onPlay(channel) }, onFocus: { onFocus(channel) })
                            }
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
            }
            .focusSection()
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
                            MovieCard(channel: channel, onClick: { onPlay(channel) }, onFocus: { onFocus(channel) })
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 100)
                }
                .focusSection()
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
            .focusSection()
        }
    }
}
