import SwiftUI

// A simple state machine for navigation without NavigationView overhead
enum NavigationDestination: Equatable {
    case home
    case details(Channel)
    case player(Channel)
    case settings
    case addPlaylist
    
    static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
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
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        ZStack {
            // Switcher Logic
            switch currentDestination {
            case .home:
                HomeView(
                    onPlayChannel: { channel in
                        if channel.type == "live" {
                            // Live TV goes straight to player
                            currentDestination = .player(channel)
                        } else {
                            // Movies/Series go to Details Page
                            currentDestination = .details(channel)
                        }
                    },
                    onAddPlaylist: { currentDestination = .addPlaylist },
                    onSettings: { currentDestination = .settings }
                )
                .transition(.opacity)
                
            case .details(let channel):
                DetailsView(
                    channel: channel,
                    onPlay: { playableChannel in
                        // Navigate to player with the specific file/episode
                        currentDestination = .player(playableChannel)
                    },
                    onBack: {
                        currentDestination = .home
                    }
                )
                .transition(.move(edge: .trailing))
                
            case .player(let channel):
                PlayerView(
                    channel: channel,
                    onBack: {
                        // When player exits:
                        // If it was a live channel, go Home.
                        // If it was a VOD/Series, we *could* go back to Details,
                        // but for now going Home is a safe default to avoid state complexity.
                        currentDestination = .home
                    }
                )
                .transition(.move(edge: .bottom))
                
            case .settings:
                SettingsView(onBack: { currentDestination = .home })
                    .transition(.move(edge: .trailing))
                
            case .addPlaylist:
                AddPlaylistView(
                    onPlaylistAdded: { currentDestination = .home },
                    onBack: { currentDestination = .home }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: currentDestination)
    }
}
