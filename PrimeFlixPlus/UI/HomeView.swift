import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlayChannel: (Channel) -> Void
    var onAddPlaylist: () -> Void
    var onSettings: () -> Void
    
    // Focus State for Navigation Logic
    @FocusState private var focusedSection: HomeSection?
    @Namespace private var scrollSpace
    
    enum HomeSection: Hashable {
        case tabs
        case categories
        case content(String) // Channel ID
    }
    
    // Grid Layout
    let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 40)
    ]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.selectedPlaylist == nil {
                // --- PROFILE/PLAYLIST SELECTOR ---
                VStack(spacing: 40) {
                    Text("Who is watching?")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 40) {
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
                        
                        ForEach(viewModel.playlists) { playlist in
                            Button(action: { viewModel.selectPlaylist(playlist) }) {
                                VStack {
                                    Image(systemName: "person.tv.fill")
                                        .font(.system(size: 50))
                                        .padding()
                                    Text(playlist.title)
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
                        
                        // 1. Header Tabs
                        HStack(spacing: 30) {
                            tabButton(title: "SERIES", type: .series)
                            tabButton(title: "MOVIES", type: .movie)
                            tabButton(title: "LIVE TV", type: .live)
                            Spacer()
                            Button(action: onSettings) {
                                Image(systemName: "gearshape")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 60)
                        .padding(.bottom, 20)
                        .background(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                        .id("TopAnchor")
                        
                        // 2. Scrollable Content
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 30) {
                                
                                // Categories (Chips)
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
                                        }
                                    }
                                    .padding(.horizontal, 60)
                                    .padding(.vertical, 20)
                                }
                                
                                // Content Grid
                                if viewModel.isLoading {
                                    HStack {
                                        Spacer()
                                        ProgressView(viewModel.loadingMessage)
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
                        // If user is deep in the grid (content focused), scroll to top first
                        if case .content = focusedSection {
                            withAnimation {
                                scrollProxy.scrollTo("TopAnchor", anchor: .top)
                                focusedSection = .categories // Move focus to chips
                            }
                        }
                        // If user is at categories or tabs, go back to Profile Select
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
    
    private func tabButton(title: String, type: StreamType) -> some View {
        Button(action: { viewModel.selectTab(type) }) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(viewModel.selectedTab == type ? .cyan : .gray)
                .scaleEffect(viewModel.selectedTab == type ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .focused($focusedSection, equals: .tabs)
    }
}
