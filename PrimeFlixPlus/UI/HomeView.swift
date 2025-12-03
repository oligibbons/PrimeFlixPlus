import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlayChannel: (Channel) -> Void
    var onAddPlaylist: () -> Void
    var onSettings: () -> Void
    
    @FocusState private var focusedSectionId: UUID?
    @FocusState private var isTabFocused: Bool
    
    // Grid Columns for Drill Down
    let gridColumns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 40)]
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            if viewModel.selectedPlaylist == nil {
                // PROFILE SELECTOR (Unchanged Logic, simplified visual)
                profileSelector
            } else if let categoryTitle = viewModel.drillDownCategory {
                // DRILL DOWN GRID VIEW
                drillDownView(title: categoryTitle)
                    .transition(.move(edge: .trailing))
            } else {
                // MAIN RAILS VIEW
                mainDashboard
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.drillDownCategory)
        .onAppear { viewModel.configure(repository: repository) }
    }
    
    // MARK: - Main Dashboard
    var mainDashboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 1. Header / Tabs
            HStack(spacing: 40) {
                // Branding
                Text("PrimeFlix+")
                    .font(.custom("Exo2-Bold", size: 32))
                    .foregroundColor(.cyan)
                
                Spacer()
                
                // Tabs
                tabButton(title: "Series", type: .series)
                tabButton(title: "Movies", type: .movie)
                tabButton(title: "Live TV", type: .live)
                
                Spacer()
                
                // Settings
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
            .padding(.horizontal, 60)
            .padding(.bottom, 20)
            .background(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            
            // 2. Content Rails
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Curating Content...")
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 40) {
                        ForEach(viewModel.sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                // Section Header
                                Button(action: { viewModel.openCategory(section) }) {
                                    HStack {
                                        Text(section.title)
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(focusedSectionId == section.id ? .cyan : .white)
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .opacity(focusedSectionId == section.id ? 1 : 0)
                                    }
                                }
                                .buttonStyle(.plain)
                                .focused($focusedSectionId, equals: section.id)
                                .padding(.horizontal, 60)
                                
                                // Horizontal Rail
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 40) {
                                        ForEach(section.items) { channel in
                                            // Differentiate Card Style based on Section Type
                                            if section.type == .continueWatching {
                                                ContinueWatchingCard(channel: channel) {
                                                    onPlayChannel(channel)
                                                }
                                            } else {
                                                MovieCard(channel: channel) {
                                                    onPlayChannel(channel)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 60)
                                    .padding(.vertical, 30) // Space for focus expansion
                                }
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
    }
    
    // MARK: - Drill Down Grid
    func drillDownView(title: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Button(action: { viewModel.closeDrillDown() }) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text(title)
                            .font(.title)
                            .fontWeight(.bold)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(60)
            
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 60) {
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
        .background(Color.black)
        .onExitCommand {
            viewModel.closeDrillDown()
        }
    }
    
    // MARK: - Components
    
    private var profileSelector: some View {
        VStack(spacing: 40) {
            Text("Who is watching?").font(.title).foregroundColor(.white)
            HStack(spacing: 40) {
                Button(action: onAddPlaylist) {
                    VStack {
                        Image(systemName: "plus").font(.largeTitle)
                        Text("Add Profile")
                    }
                    .frame(width: 250, height: 180)
                }
                .buttonStyle(.card)
                
                ForEach(viewModel.playlists) { playlist in
                    Button(action: { viewModel.selectPlaylist(playlist) }) {
                        VStack {
                            Image(systemName: "person.fill").font(.largeTitle)
                            Text(playlist.title)
                        }
                        .frame(width: 250, height: 180)
                    }
                    .buttonStyle(.card)
                }
            }
        }
    }
    
    private func tabButton(title: String, type: StreamType) -> some View {
        Button(action: { viewModel.selectTab(type) }) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(viewModel.selectedTab == type ? .cyan : .gray)
                .scaleEffect(viewModel.selectedTab == type ? 1.1 : 1.0)
                .animation(.spring(), value: viewModel.selectedTab)
        }
        .buttonStyle(.plain)
        .focused($isTabFocused)
    }
}
