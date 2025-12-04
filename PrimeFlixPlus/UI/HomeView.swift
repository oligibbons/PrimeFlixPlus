import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlayChannel: (Channel) -> Void
    var onAddPlaylist: () -> Void
    var onSettings: () -> Void
    var onSearch: () -> Void
    
    @FocusState private var focusedSectionId: UUID?
    @FocusState private var focusedTab: StreamType?
    
    // Grid for drill-down views
    let gridColumns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 40)]
    
    var body: some View {
        ZStack {
            if viewModel.selectedPlaylist == nil {
                profileSelector
            } else if let categoryTitle = viewModel.drillDownCategory {
                drillDownView(title: categoryTitle)
                    .transition(.move(edge: .trailing))
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.drillDownCategory)
        .onAppear { viewModel.configure(repository: repository) }
    }
    
    // MARK: - Main Feed
    var mainContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                
                // 1. Header: Greeting & Profile
                HStack {
                    VStack(alignment: .leading) {
                        Text("Welcome Back")
                            .cinemeltBody()
                            .opacity(0.7)
                        Text(viewModel.selectedPlaylist?.title ?? "Guest")
                            .cinemeltTitle()
                    }
                    Spacer()
                }
                .padding(.top, 40)
                .padding(.horizontal, 50)
                
                // 2. LOGIC RESTORED: Content Filter Bar (Movies | Series | Live)
                HStack(spacing: 20) {
                    filterTab(title: "Movies", type: .movie)
                    filterTab(title: "Series", type: .series)
                    filterTab(title: "Live TV", type: .live)
                }
                .padding(.horizontal, 50)
                .padding(.bottom, 20)
                
                // 3. Content Lanes
                if viewModel.isLoading {
                    loadingState
                } else {
                    LazyVStack(alignment: .leading, spacing: 50) {
                        ForEach(viewModel.sections) { section in
                            VStack(alignment: .leading, spacing: 15) {
                                // Section Header
                                Button(action: { viewModel.openCategory(section) }) {
                                    HStack(spacing: 10) {
                                        Text(section.title)
                                            .font(CinemeltTheme.fontTitle(28))
                                            .foregroundColor(focusedSectionId == section.id ? CinemeltTheme.accent : CinemeltTheme.cream)
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .opacity(focusedSectionId == section.id ? 1 : 0)
                                    }
                                }
                                .buttonStyle(.plain)
                                .focused($focusedSectionId, equals: section.id)
                                .padding(.horizontal, 50)
                                
                                // Horizontal Lane
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 40) {
                                        ForEach(section.items) { channel in
                                            cardView(for: channel, sectionType: section.type)
                                        }
                                    }
                                    .padding(.horizontal, 50)
                                    .padding(.vertical, 30) // Vertical padding ensures scale effect doesn't clip
                                }
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
    }
    
    // MARK: - Components
    
    // The Restored Filter Button
    private func filterTab(title: String, type: StreamType) -> some View {
        Button(action: {
            withAnimation {
                viewModel.selectTab(type)
            }
        }) {
            Text(title)
                .font(CinemeltTheme.fontTitle(22))
                .fontWeight(.bold)
                .foregroundColor(viewModel.selectedTab == type ? .black : CinemeltTheme.cream)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if viewModel.selectedTab == type {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(CinemeltTheme.accent)
                                .shadow(color: CinemeltTheme.accent.opacity(0.6), radius: 10)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                        }
                    }
                )
        }
        .buttonStyle(.card)
        .focused($focusedTab, equals: type)
        .scaleEffect(focusedTab == type ? 1.1 : 1.0)
    }
    
    var loadingState: some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                ProgressView()
                    .tint(CinemeltTheme.accent)
                    .scaleEffect(1.5)
                Text("Loading Library...")
                    .font(CinemeltTheme.fontBody(20))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.top, 100)
    }
    
    @ViewBuilder
    private func cardView(for channel: Channel, sectionType: HomeSection.SectionType) -> some View {
        if case .continueWatching = sectionType {
            ContinueWatchingCard(channel: channel) {
                onPlayChannel(channel)
            }
        } else {
            MovieCard(channel: channel) {
                onPlayChannel(channel)
            }
        }
    }
    
    // MARK: - Drill Down (Grid)
    
    func drillDownView(title: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Button(action: { viewModel.closeDrillDown() }) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text(title)
                            .font(CinemeltTheme.fontTitle(36))
                            .foregroundColor(CinemeltTheme.cream)
                    }
                }
                .buttonStyle(.plain)
                .padding(50)
                Spacer()
            }
            
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 60) {
                    ForEach(viewModel.displayedGridChannels) { channel in
                        MovieCard(channel: channel) {
                            onPlayChannel(channel)
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.bottom, 100)
            }
        }
        .background(CinemeltTheme.mainBackground)
        .onExitCommand {
            viewModel.closeDrillDown()
        }
    }
    
    // MARK: - Profile Selector
    
    private var profileSelector: some View {
        VStack(spacing: 50) {
            Text("Who is watching?")
                .font(CinemeltTheme.fontTitle(48))
                .foregroundColor(CinemeltTheme.cream)
            
            HStack(spacing: 60) {
                Button(action: onAddPlaylist) {
                    VStack {
                        Image(systemName: "plus")
                            .font(.system(size: 50))
                            .padding()
                        Text("Add Profile")
                            .font(CinemeltTheme.fontBody(24))
                    }
                    .frame(width: 250, height: 250)
                    .background(CinemeltTheme.glassSurface)
                    .clipShape(Circle())
                }
                .buttonStyle(.card)
                
                ForEach(viewModel.playlists) { playlist in
                    Button(action: { viewModel.selectPlaylist(playlist) }) {
                        VStack {
                            Text(String(playlist.title.prefix(1)).uppercased())
                                .font(CinemeltTheme.fontTitle(80))
                                .foregroundColor(CinemeltTheme.accent)
                            
                            Text(playlist.title)
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(CinemeltTheme.cream)
                        }
                        .frame(width: 250, height: 250)
                        .background(CinemeltTheme.glassSurface)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.card)
                }
            }
        }
    }
}
