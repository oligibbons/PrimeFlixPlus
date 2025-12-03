import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlayChannel: (Channel) -> Void
    var onAddPlaylist: () -> Void
    var onSettings: () -> Void
    
    // Focus State for Navigation Logic
    @FocusState private var focusedSection: HomeSection?
    
    enum HomeSection: Hashable {
        case tabs
        case categories
        case content(String) // Channel ID
    }
    
    // Grid Layout: Adaptive width for posters
    let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 40)
    ]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.selectedPlaylist == nil {
                // --- PROFILE/PLAYLIST SELECTOR ---
                VStack(spacing: 40) {
                    Text("Who is watching?")
                        .font(.custom("Exo2-Bold", size: 50))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 40) {
                        // Add Profile Button
                        Button(action: onAddPlaylist) {
                            VStack {
                                Image(systemName: "plus")
                                    .font(.system(size: 50))
                                    .padding()
                                Text("Add Profile")
                            }
                            .frame(width: 300, height: 200)
                        }
                        .buttonStyle(.card)
                        
                        // Existing Profiles
                        ForEach(viewModel.playlists) { playlist in
                            Button(action: { viewModel.selectPlaylist(playlist) }) {
                                VStack {
                                    Image(systemName: "person.tv.fill")
                                        .font(.system(size: 50))
                                        .padding()
                                    Text(playlist.title)
                                        .fontWeight(.semibold)
                                }
                                .frame(width: 300, height: 200)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
            } else {
                // --- MAIN DASHBOARD ---
                ScrollViewReader { scrollProxy in
                    VStack(alignment: .leading, spacing: 0) {
                        
                        // 1. Header / Tabs
                        HStack(spacing: 30) {
                            // Tab Buttons
                            tabButton(title: "SERIES", type: .series)
                            tabButton(title: "MOVIES", type: .movie)
                            tabButton(title: "LIVE TV", type: .live)
                            
                            Spacer()
                            
                            // Settings Button
                            Button(action: onSettings) {
                                Image(systemName: "gearshape")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 60)
                        .padding(.bottom, 20)
                        .background(
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        )
                        .id("TopAnchor") // Anchor for scrolling to top
                        
                        // 2. Scrollable Content Area
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 30) {
                                
                                // Category Chips (Horizontal Scroll)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(viewModel.categories, id: \.self) { category in
                                            Button(action: { viewModel.selectCategory(category) }) {
                                                Text(category)
                                                    .fontWeight(.semibold)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                            }
                                            .buttonStyle(.card)
                                            .focused($focusedSection, equals: .categories)
                                            .foregroundColor(viewModel.selectedCategory == category ? .white : .gray)
                                        }
                                    }
                                    .padding(.horizontal, 60)
                                    .padding(.vertical, 20)
                                }
                                
                                // Main Content Grid
                                if viewModel.isLoading {
                                    HStack {
                                        Spacer()
                                        ProgressView(viewModel.loadingMessage)
                                            .scaleEffect(1.5)
                                        Spacer()
                                    }
                                    .frame(height: 300)
                                } else {
                                    LazyVGrid(columns: columns, spacing: 60) {
                                        ForEach(viewModel.displayedChannels) { channel in
                                            MovieCard(channel: channel) {
                                                onPlayChannel(channel)
                                            }
                                            .focused($focusedSection, equals: .content(channel.url))
                                        }
                                    }
                                    .padding(.horizontal, 60)
                                    .padding(.bottom, 100)
                                }
                            }
                        }
                    }
                    // --- SMART NAVIGATION LOGIC ---
                    .onExitCommand {
                        // 1. If focus is deep in content, scroll to top first
                        if case .content = focusedSection {
                            withAnimation {
                                scrollProxy.scrollTo("TopAnchor", anchor: .top)
                                focusedSection = .categories // Move focus up to chips
                            }
                        }
                        // 2. If already at categories or tabs, go back to Profile Select
                        else {
                            withAnimation {
                                viewModel.selectedPlaylist = nil
                            }
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.configure(repository: repository) }
    }
    
    // Helper for Tab Buttons
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
        .focused($focusedSection, equals: .tabs)
    }
}
