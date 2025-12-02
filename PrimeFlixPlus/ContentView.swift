import SwiftUI

enum NavigationDestination: Equatable {
    case home
    case player(Channel)
    case settings
    case addPlaylist // New Route
    
    static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.settings, .settings): return true
        case (.addPlaylist, .addPlaylist): return true
        case (.player(let c1), .player(let c2)): return c1.url == c2.url
        default: return false
        }
    }
}

struct ContentView: View {
    @State private var currentDestination: NavigationDestination = .home
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        ZStack {
            switch currentDestination {
            case .home:
                HomeView(
                    onPlayChannel: { channel in
                        currentDestination = .player(channel)
                    },
                    onAddPlaylist: {
                        currentDestination = .addPlaylist // Fixed: Now goes to Add Screen
                    },
                    onSettings: {
                        currentDestination = .settings
                    }
                )
                .transition(.opacity)
                
            case .player(let channel):
                PlayerView(
                    channel: channel,
                    onBack: {
                        currentDestination = .home
                    }
                )
                .transition(.move(edge: .bottom))
                
            case .settings:
                SettingsView(
                    onBack: {
                        currentDestination = .home
                    }
                )
                .transition(.move(edge: .trailing))
                
            case .addPlaylist:
                AddPlaylistView(
                    onPlaylistAdded: {
                        currentDestination = .home // Go back to home (which will reload playlists)
                    },
                    onBack: {
                        currentDestination = .home
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentDestination)
    }
}
