import SwiftUI

// Navigation State
// FIXED: Added Hashable conformance to satisfy Sidebar focus requirements
enum NavigationDestination: Hashable {
    case home
    case search
    case details(Channel)
    case player(Channel)
    case settings
    case addPlaylist
    
    // Explicit Equatable Logic (Keep logic strictly on URLs for channels)
    static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.search, .search): return true
        case (.settings, .settings): return true
        case (.addPlaylist, .addPlaylist): return true
        case (.player(let c1), .player(let c2)): return c1.url == c2.url
        case (.details(let c1), .details(let c2)): return c1.url == c2.url
        default: return false
        }
    }
    
    // Explicit Hashable Logic (CRITICAL FIX)
    func hash(into hasher: inout Hasher) {
        switch self {
        case .home: hasher.combine(0)
        case .search: hasher.combine(1)
        case .details(let c):
            hasher.combine(2)
            hasher.combine(c.url) // Hash the URL to match Equatable logic
        case .player(let c):
            hasher.combine(3)
            hasher.combine(c.url)
        case .settings: hasher.combine(4)
        case .addPlaylist: hasher.combine(5)
        }
    }
}

struct ContentView: View {
    @State private var currentDestination: NavigationDestination = .home
    @State private var navigationStack: [NavigationDestination] = []
    
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // Focus state to manage interaction between sidebar and content
    @FocusState private var isSidebarFocused: Bool
    
    var body: some View {
        ZStack {
            // 1. Global Cinematic Background
            CinemeltTheme.mainBackground
                .ignoresSafeArea()
            
            // 2. Main Layout (Sidebar + Content)
            HStack(spacing: 0) {
                
                // LEFT: Glassmorphic Sidebar
                // We hide the sidebar in Player mode for full immersion
                if !isPlayerMode {
                    SidebarView(currentSelection: $currentDestination)
                        .zIndex(2)
                        .transition(.move(edge: .leading))
                }
                
                // RIGHT: Content Area
                ZStack {
                    switch currentDestination {
                    case .home:
                        HomeView(
                            onPlayChannel: { channel in navigateToContent(channel) },
                            onAddPlaylist: { currentDestination = .addPlaylist },
                            onSettings: { currentDestination = .settings },
                            onSearch: { currentDestination = .search }
                        )
                        
                    case .search:
                        SearchView(
                            onPlay: { channel in navigateToContent(channel) }
                        )
                        
                    case .details(let channel):
                        DetailsView(
                            channel: channel,
                            onPlay: { playable in
                                // Push to stack so we can return to Details
                                navigate(to: .player(playable))
                            },
                            onBack: { goBack() }
                        )
                        
                    case .player(let channel):
                        PlayerView(
                            channel: channel,
                            onBack: { goBack() }
                        )
                        
                    case .settings:
                        SettingsView(onBack: { goBack() })
                        
                    case .addPlaylist:
                        AddPlaylistView(
                            onPlaylistAdded: {
                                navigationStack.removeAll()
                                currentDestination = .home
                            },
                            onBack: { goBack() }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Use a subtle fade when switching main tabs, moves for details
                .animation(.easeInOut(duration: 0.35), value: currentDestination)
            }
        }
        // Handle physical Menu button on Apple TV Remote
        .onExitCommand {
            if !navigationStack.isEmpty {
                goBack()
            } else if currentDestination != .home {
                currentDestination = .home
            }
        }
    }
    
    // MARK: - Helpers
    
    var isPlayerMode: Bool {
        if case .player = currentDestination { return true }
        return false
    }
    
    private func navigate(to destination: NavigationDestination) {
        if currentDestination == destination { return }
        navigationStack.append(currentDestination)
        currentDestination = destination
    }
    
    private func goBack() {
        if let previous = navigationStack.popLast() {
            currentDestination = previous
        } else {
            currentDestination = .home
        }
    }
    
    private func navigateToContent(_ channel: Channel) {
        if channel.type == "live" {
            navigate(to: .player(channel))
        } else {
            navigate(to: .details(channel))
        }
    }
}
