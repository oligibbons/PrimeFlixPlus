// oligibbons/primeflixplus/PrimeFlixPlus-73fc471b3826ec01f10236d5c79ae256450974b4/PrimeFlixPlus/ContentView.swift

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
    case speedTest
    
    static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.search, .search): return true
        case (.continueWatching, .continueWatching): return true
        case (.favorites, .favorites): return true
        case (.settings, .settings): return true
        case (.addPlaylist, .addPlaylist): return true
        case (.speedTest, .speedTest): return true
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
        case .speedTest: hasher.combine(8)
        }
    }
}

struct ContentView: View, Equatable {
    // MARK: - Equatable Conformance
    // Strict false ensures the view redraws on @State changes like showVPNWarning
    static func == (lhs: ContentView, rhs: ContentView) -> Bool {
        return false
    }
    
    @State private var currentDestination: NavigationDestination = .home
    @State private var navigationStack: [NavigationDestination] = []
    
    // VPN Warning State
    @State private var showVPNWarning: Bool = false
    @State private var pendingPlayable: Channel? = nil
    
    // Dependency Injection
    let repository: PrimeFlixRepository
    
    // Layout Constants
    private let collapsedSidebarWidth: CGFloat = 100
    
    var body: some View {
        ZStack(alignment: .leading) {
            // 1. Global Cinematic Background
            CinemeltTheme.mainBackground
                .ignoresSafeArea()
            
            // 2. Sidebar
            if !isPlayerMode && currentDestination != .speedTest {
                SidebarView(currentSelection: $currentDestination)
                    .zIndex(2)
                    .transition(.move(edge: .leading))
                    .disabled(showVPNWarning)
                    .blur(radius: showVPNWarning ? 10 : 0)
            }
            
            // 3. Main Content
            ZStack {
                switch currentDestination {
                case .home:
                    HomeView(
                        onPlayChannel: { channel in navigateToContent(channel) },
                        onAddPlaylist: { currentDestination = .addPlaylist },
                        onSettings: { currentDestination = .settings },
                        onSearch: { _ in currentDestination = .search }
                    )
                    
                case .search:
                                    SearchView(
                                        repository: repository, // <--- Added this argument
                                        onPlay: { channel in navigateToContent(channel) },
                                        onBack: { goBack() }
                                    )
                    )
                
                case .continueWatching:
                    ContinueWatchingView(
                        onPlay: { channel in navigateToContent(channel) },
                        onBack: { goBack() }
                    )
                
                case .favorites:
                    FavoritesView(
                        onPlay: { channel in navigateToContent(channel) },
                        onBack: { goBack() }
                    )
                    
                case .details(let channel):
                    DetailsView(
                        channel: channel,
                        onPlay: { playable in
                            attemptPlayback(playable)
                        },
                        onBack: { goBack() }
                    )
                    
                case .player(let channel):
                    PlayerView(
                        channel: channel,
                        onBack: { goBack() },
                        onPlayChannel: { nextChannel in
                            attemptPlayback(nextChannel, replaceCurrent: true)
                        }
                    )
                    
                case .settings:
                    SettingsView(
                        onBack: { goBack() },
                        onSpeedTest: { navigate(to: .speedTest) }
                    )
                    
                case .addPlaylist:
                    AddPlaylistView(
                        repository: repository,
                        onPlaylistAdded: {
                            navigationStack.removeAll()
                            currentDestination = .home
                        },
                        onBack: { goBack() }
                    )
                    .equatable()
                
                case .speedTest:
                    NetworkSpeedTestView(onBack: { goBack() })
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, isPaddingActive ? collapsedSidebarWidth : 0)
            .animation(.easeInOut(duration: 0.35), value: currentDestination)
            .focusSection()
            .zIndex(1)
            // Blur the content when warning is active
            .disabled(showVPNWarning)
            .blur(radius: showVPNWarning ? 10 : 0)
            
            // 4. Global VPN Warning Overlay
            if showVPNWarning {
                VPNWarningView(
                    onProceed: {
                        print("[VPN UI] User chose Proceed")
                        if let channel = pendingPlayable {
                            forcePlay(channel)
                        }
                        closeWarning()
                    },
                    onCancel: {
                        print("[VPN UI] User chose Return")
                        closeWarning()
                    }
                )
                .zIndex(999)
                .transition(.opacity.animation(.easeInOut))
            }
            
            // 5. DEBUG INDICATOR (Remove for production release)
            if !isPlayerMode && currentDestination != .speedTest {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            let status = VPNDetector.checkVPNStatus()
                            Circle()
                                .fill(status.isActive ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(status.isActive ? "VPN: Safe (\(status.interfaceName ?? "?"))" : "VPN: Unsafe")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                        .padding(.top, 40)
                        .padding(.trailing, 40)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
                .zIndex(50)
            }
        }
        .onExitCommand {
            if showVPNWarning {
                closeWarning()
            } else if !navigationStack.isEmpty {
                goBack()
            } else if currentDestination != .home {
                currentDestination = .home
            }
        }
    }
    
    // MARK: - Logic & Helpers
    
    private func attemptPlayback(_ channel: Channel, replaceCurrent: Bool = false) {
        let vpnStatus = VPNDetector.checkVPNStatus()
        print("[VPN CHECK] Status: \(vpnStatus.isActive) Interface: \(vpnStatus.interfaceName ?? "None")")
        
        if vpnStatus.isActive {
            // Safe -> Play
            if replaceCurrent {
                currentDestination = .player(channel)
            } else {
                navigate(to: .player(channel))
            }
        } else {
            // Unsafe -> Show Warning
            print("[VPN CHECK] Triggering Warning")
            self.pendingPlayable = channel
            withAnimation {
                self.showVPNWarning = true
            }
        }
    }
    
    private func forcePlay(_ channel: Channel) {
        if case .player = currentDestination {
            currentDestination = .player(channel)
        } else {
            navigate(to: .player(channel))
        }
    }
    
    private func closeWarning() {
        withAnimation {
            showVPNWarning = false
            pendingPlayable = nil
        }
    }
    
    var isPlayerMode: Bool {
        if case .player = currentDestination { return true }
        return false
    }
    
    var isPaddingActive: Bool {
        return !isPlayerMode && currentDestination != .speedTest
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
            attemptPlayback(channel)
        } else {
            navigate(to: .details(channel))
        }
    }
}
