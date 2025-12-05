import SwiftUI

// Navigation State
enum NavigationDestination: Hashable {
    case home
    case search
    case continueWatching
    case favorites
    case details(Channel)
    case player(Channel)
    case settings
    case addPlaylist
    
    static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.search, .search): return true
        case (.continueWatching, .continueWatching): return true
        case (.favorites, .favorites): return true
        case (.settings, .settings): return true
        case (.addPlaylist, .addPlaylist): return true
        case (.player(let c1), .player(let c2)): return c1.url == c2.url
        case (.details(let c1), .details(let c2)): return c1.url == c2.url
        default: return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .home: hasher.combine(0)
        case .search: hasher.combine(1)
        case .details(let c):
            hasher.combine(2)
            hasher.combine(c.url)
        case .player(let c):
            hasher.combine(3)
            hasher.combine(c.url)
        case .settings: hasher.combine(4)
        case .addPlaylist: hasher.combine(5)
        case .continueWatching: hasher.combine(6)
        case .favorites: hasher.combine(7)
        }
    }
}

struct ContentView: View, Equatable {
    // MARK: - Equatable Conformance
    // Stops this view from redrawing when parent (App) state changes
    static func == (lhs: ContentView, rhs: ContentView) -> Bool {
        return true
    }
    
    @State private var currentDestination: NavigationDestination = .home
    @State private var navigationStack: [NavigationDestination] = []
    
    // Dependency Injection: Passed as 'let' to avoid observing changes
    let repository: PrimeFlixRepository
    
    // Layout Constants
    private let collapsedSidebarWidth: CGFloat = 100
    
    var body: some View {
        ZStack(alignment: .leading) {
            // 1. Global Cinematic Background
            CinemeltTheme.mainBackground
                .ignoresSafeArea()
            
            // 2. Sidebar
            if !isPlayerMode {
                SidebarView(currentSelection: $currentDestination)
                    .zIndex(2)
                    .transition(.move(edge: .leading))
            }
            
            // 3. Main Content
            ZStack {
                switch currentDestination {
                case .home:
                    HomeView(
                        onPlayChannel: { channel in navigateToContent(channel) },
                        onAddPlaylist: { currentDestination = .addPlaylist },
                        onSettings: { currentDestination = .settings },
                        // FIX: Explicitly ignore StreamType arg to satisfy closure signature
                        onSearch: { _ in currentDestination = .search }
                    )
                    
                case .search:
                    // FIX: Added missing onBack closure
                    SearchView(
                        onPlay: { channel in navigateToContent(channel) },
                        onBack: { goBack() }
                    )
                
                case .continueWatching:
                    ContinueWatchingView(
                        onPlay: { channel in navigateToContent(channel) },
                        onBack: { currentDestination = .home }
                    )
                    
                case .favorites:
                    FavoritesView(
                        onPlay: { channel in navigateToContent(channel) },
                        onBack: { currentDestination = .home }
                    )
                    
                case .details(let channel):
                    DetailsView(
                        channel: channel,
                        onPlay: { playable in
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
                    // Using .equatable() + decoupled repository ensures this view remains stable
                    AddPlaylistView(
                        repository: repository,
                        onPlaylistAdded: {
                            navigationStack.removeAll()
                            currentDestination = .home
                        },
                        onBack: { goBack() }
                    )
                    .equatable()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, isPlayerMode ? 0 : collapsedSidebarWidth)
            .animation(.easeInOut(duration: 0.35), value: currentDestination)
            .focusSection()
            .zIndex(1)
        }
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
