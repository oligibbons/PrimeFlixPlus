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
    let gridColumns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 50)]
    
    var body: some View {
        ZStack {
            // 1. Global Mesh Background
            CinemeltTheme.mainBackground
            
            // 2. State Content
            if viewModel.selectedPlaylist == nil {
                profileSelector
                    .transition(.opacity)
            } else if let categoryTitle = viewModel.drillDownCategory {
                drillDownView(title: categoryTitle)
                    .transition(.move(edge: .trailing))
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.drillDownCategory)
        .onAppear { viewModel.configure(repository: repository) }
    }
    
    // MARK: - Main Feed Structure
    
    var mainContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                headerSection
                filterSection
                lanesSection
            }
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome Back,")
                    .cinemeltBody()
                    .opacity(0.6)
                
                Text(viewModel.selectedPlaylist?.title ?? "Guest")
                    .cinemeltTitle()
                    .font(CinemeltTheme.fontTitle(60))
                    .cinemeltGlow()
            }
            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 60)
    }
    
    private var filterSection: some View {
        HStack(spacing: 0) {
            filterTab(title: "Movies", type: .movie)
            filterTab(title: "Series", type: .series)
            filterTab(title: "Live TV", type: .live)
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.05))
        .cornerRadius(25)
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 60)
        .padding(.top, 20)
        .padding(.bottom, 30)
    }
    
    private var lanesSection: some View {
        Group {
            if viewModel.isLoading {
                loadingState
            } else {
                LazyVStack(alignment: .leading, spacing: 40) {
                    ForEach(viewModel.sections) { section in
                        VStack(alignment: .leading, spacing: 20) {
                            // Section Header
                            Button(action: { viewModel.openCategory(section) }) {
                                HStack(spacing: 15) {
                                    Text(section.title)
                                        .font(CinemeltTheme.fontTitle(32))
                                        .foregroundColor(focusedSectionId == section.id ? CinemeltTheme.accent : CinemeltTheme.cream)
                                        .shadow(color: focusedSectionId == section.id ? CinemeltTheme.accent.opacity(0.6) : .clear, radius: 10)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.headline)
                                        .foregroundColor(CinemeltTheme.accent)
                                        .opacity(focusedSectionId == section.id ? 1 : 0)
                                        .offset(x: focusedSectionId == section.id ? 5 : 0)
                                }
                            }
                            .buttonStyle(.plain)
                            .focused($focusedSectionId, equals: section.id)
                            .padding(.horizontal, 60)
                            
                            // Horizontal Lane
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 50) {
                                    ForEach(section.items) { channel in
                                        cardView(for: channel, sectionType: section.type)
                                    }
                                }
                                .padding(.horizontal, 60)
                                .padding(.vertical, 40)
                            }
                        }
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - Components
    
    private func filterTab(title: String, type: StreamType) -> some View {
        Button(action: {
            withAnimation {
                viewModel.selectTab(type)
            }
        }) {
            Text(title)
                .font(CinemeltTheme.fontTitle(24))
                .foregroundColor(viewModel.selectedTab == type ? .black : CinemeltTheme.cream)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        if viewModel.selectedTab == type {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(CinemeltTheme.accent)
                                .matchedGeometryEffect(id: "activeFilter", in: Namespace().wrappedValue)
                                .shadow(color: CinemeltTheme.accent.opacity(0.6), radius: 10)
                        }
                    }
                )
        }
        .buttonStyle(.card)
        .focused($focusedTab, equals: type)
        .scaleEffect(focusedTab == type ? 1.05 : 1.0)
    }
    
    var loadingState: some View {
        HStack {
            Spacer()
            VStack(spacing: 30) {
                ProgressView()
                    .tint(CinemeltTheme.accent)
                    .scaleEffect(2.0)
                Text("Loading Your Library...")
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(CinemeltTheme.cream.opacity(0.5))
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
        ZStack {
            // Blurred backdrop for focus
            CinemeltTheme.mainBackground
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            
            VStack(alignment: .leading) {
                HStack {
                    Button(action: { viewModel.closeDrillDown() }) {
                        HStack(spacing: 15) {
                            Image(systemName: "arrow.left")
                            Text(title)
                                .font(CinemeltTheme.fontTitle(50))
                                .cinemeltGlow()
                        }
                        .foregroundColor(CinemeltTheme.cream)
                    }
                    .buttonStyle(.plain)
                    .padding(60)
                    Spacer()
                }
                
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 80) {
                        ForEach(viewModel.displayedGridChannels) { channel in
                            MovieCard(channel: channel) {
                                onPlayChannel(channel)
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 100)
                }
            }
        }
        .onExitCommand {
            viewModel.closeDrillDown()
        }
    }
    
    // MARK: - Profile Selector
    
    private var profileSelector: some View {
        VStack(spacing: 60) {
            VStack(spacing: 10) {
                Text("Who is watching?")
                    .font(CinemeltTheme.fontTitle(60))
                    .foregroundColor(CinemeltTheme.cream)
                    .cinemeltGlow()
                
                Text("Select a profile to continue")
                    .cinemeltBody()
            }
            
            HStack(spacing: 80) {
                // Add Button
                Button(action: onAddPlaylist) {
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
                    .cinemeltGlass(radius: 150) // Circular Glass
                }
                .buttonStyle(CinemeltCardButtonStyle())
                
                // Existing Profiles
                ForEach(viewModel.playlists) { playlist in
                    Button(action: { viewModel.selectPlaylist(playlist) }) {
                        VStack {
                            Text(String(playlist.title.prefix(1)).uppercased())
                                .font(CinemeltTheme.fontTitle(100))
                                .foregroundColor(CinemeltTheme.accent)
                                .shadow(color: CinemeltTheme.accent.opacity(0.8), radius: 20)
                            
                            Text(playlist.title)
                                .font(CinemeltTheme.fontTitle(32))
                                .foregroundColor(CinemeltTheme.cream)
                                .padding(.top, 10)
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
