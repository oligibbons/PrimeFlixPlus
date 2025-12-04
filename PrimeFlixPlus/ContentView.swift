import SwiftUI

// Navigation State
enum NavigationDestination: Equatable {
    case home
    case search
    case details(Channel)
    case player(Channel)
    case settings
    case addPlaylist
    
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
}

struct ContentView: View {
    @State private var currentDestination: NavigationDestination = .home
    @State private var navigationStack: [NavigationDestination] = []
    
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        ZStack {
            // Switcher Logic
            switch currentDestination {
            case .home:
                HomeView(
                    onPlayChannel: { channel in
                        navigateToContent(channel)
                    },
                    onAddPlaylist: { navigate(to: .addPlaylist) },
                    onSettings: { navigate(to: .settings) },
                    onSearch: { navigate(to: .search) }
                )
                .transition(.opacity)
                
            case .search:
                SearchView(
                    onPlay: { channel in
                        navigateToContent(channel)
                    }
                )
                .transition(.move(edge: .top))
                
            case .details(let channel):
                DetailsView(
                    channel: channel,
                    onPlay: { playableChannel in
                        // Player is transient; we don't stack it usually, but let's just go direct
                        navigate(to: .player(playableChannel))
                    },
                    onBack: {
                        goBack()
                    }
                )
                .transition(.move(edge: .trailing))
                
            case .player(let channel):
                PlayerView(
                    channel: channel,
                    onBack: {
                        // When exiting player, pop back to previous (Details or Home/Search)
                        goBack()
                    }
                )
                .transition(.move(edge: .bottom))
                
            case .settings:
                SettingsView(onBack: { goBack() })
                    .transition(.move(edge: .trailing))
                
            case .addPlaylist:
                AddPlaylistView(
                    onPlaylistAdded: {
                        // Reset stack on major state change
                        navigationStack.removeAll()
                        currentDestination = .home
                    },
                    onBack: { goBack() }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: currentDestination)
        // Handle physical Menu button on Apple TV Remote to go back
        .onExitCommand {
            if currentDestination != .home {
                goBack()
            }
        }
    }
    
    // MARK: - Navigation Helpers
    
    private func navigate(to destination: NavigationDestination) {
        // Don't stack if we are just swapping tabs or redundant clicks
        if currentDestination == destination { return }
        
        // Push current to stack
        navigationStack.append(currentDestination)
        currentDestination = destination
    }
    
    private func goBack() {
        if let previous = navigationStack.popLast() {
            currentDestination = previous
        } else {
            // Default fallback
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
