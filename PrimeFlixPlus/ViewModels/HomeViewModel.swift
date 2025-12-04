import Foundation
import CoreData
import Combine

struct HomeSection: Identifiable {
    let id = UUID()
    let title: String
    let type: SectionType
    let items: [Channel]
    
    enum SectionType {
        case continueWatching
        case favorites
        case trending
        case recent
        case genre(String) // The String is the group name
        case provider(String) // e.g., Netflix
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    
    // Navigation
    @Published var selectedTab: StreamType = .movie
    
    // Data Sources
    @Published var playlists: [Playlist] = []
    @Published var selectedPlaylist: Playlist?
    
    // The "Rails" for the Home Screen
    @Published var sections: [HomeSection] = []
    
    // Loading State
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = ""
    
    // For "See All" Drill Down
    @Published var drillDownCategory: String? = nil // If non-nil, show Grid View
    @Published var displayedGridChannels: [Channel] = []
    
    // Dynamic Greeting State
    @Published var timeGreeting: String = "Welcome Back"
    @Published var witGreeting: String = "Ready to watch?"
    
    private var repository: PrimeFlixRepository?
    private let tmdbClient = TmdbClient() // Used for trending logic
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.playlists = repository.getAllPlaylists()
        if selectedPlaylist == nil, let first = playlists.first {
            selectedPlaylist = first
        }
        updateGreeting()
    }
    
    func selectPlaylist(_ playlist: Playlist) {
        self.selectedPlaylist = playlist
        updateGreeting()
        refreshContent()
    }
    
    func selectTab(_ tab: StreamType) {
        self.selectedTab = tab
        self.drillDownCategory = nil
        refreshContent()
    }
    
    // MARK: - The "Wit" Engine (Greetings)
    private func updateGreeting() {
        // 1. Calculate Time Greeting (Top Line)
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 { self.timeGreeting = "Up late?" }
        else if hour < 12 { self.timeGreeting = "Good Morning" }
        else if hour < 17 { self.timeGreeting = "Good Afternoon" }
        else { self.timeGreeting = "Good Evening" }
        
        // 2. Calculate Wit Message (Bottom Line)
        let playfulMessages = [
            "Popcorn ready?",
            "Let's find something amazing.",
            "Cinema mode: On.",
            "Your library looks great.",
            "Time to relax.",
            "Ready for the next episode?",
            "The show must go on.",
            "Discover something new.",
            "It's movie night.",
            "Press play and drift away."
        ]
        
        // Context-aware overrides
        if playlists.isEmpty {
            self.witGreeting = "Let's get you set up."
        } else if sections.isEmpty {
            self.witGreeting = "Building your cinema..."
        } else {
            // Pick a random message
            self.witGreeting = playfulMessages.randomElement() ?? "Ready to watch?"
        }
    }
    
    // MARK: - Main Refresh Logic
    
    func refreshContent() {
        guard let repo = repository else { return }
        self.isLoading = true
        self.sections = [] // Clear old
        
        Task {
            let typeStr = selectedTab.rawValue
            var newSections: [HomeSection] = []
            
            // --- LIVE TV LAYOUT ---
            if selectedTab == .live {
                // 1. Favorites
                let favs = repo.getFavorites(type: typeStr)
                if !favs.isEmpty {
                    newSections.append(HomeSection(title: "Favorite Channels", type: .favorites, items: favs))
                }
                
                // 2. Recently Watched
                let recent = repo.getSmartContinueWatching(type: typeStr)
                if !recent.isEmpty {
                    newSections.append(HomeSection(title: "Recently Watched", type: .continueWatching, items: recent))
                }
                
                // 3. All Categories (Simple alphabetical list for Live TV)
                if let pl = selectedPlaylist {
                    let allGroups = repo.getGroups(playlistUrl: pl.url, type: selectedTab)
                    for group in allGroups {
                        let items = repo.getByGenre(type: typeStr, groupName: group, limit: 20)
                        if !items.isEmpty {
                            newSections.append(HomeSection(title: group, type: .genre(group), items: items))
                        }
                    }
                }
                
            } else {
                // --- MOVIES & SERIES LAYOUT ---
                
                // 1. Continue Watching
                let resumeItems = repo.getSmartContinueWatching(type: typeStr)
                if !resumeItems.isEmpty {
                    newSections.append(HomeSection(title: "Continue Watching", type: .continueWatching, items: resumeItems))
                } else {
                    print("Debug: No continue watching items found for \(typeStr)")
                }
                
                // 2. Trending
                let trendingItems = await fetchTrendingItems(type: selectedTab)
                if !trendingItems.isEmpty {
                    newSections.append(HomeSection(title: "Trending Now", type: .trending, items: trendingItems))
                }
                
                // 3. Favorites
                let favs = repo.getFavorites(type: typeStr)
                if !favs.isEmpty {
                    newSections.append(HomeSection(title: "My List", type: .favorites, items: favs))
                }
                
                // 4. Recently Added
                let recent = repo.getRecentlyAdded(type: typeStr, limit: 20)
                if !recent.isEmpty {
                    newSections.append(HomeSection(title: "Recently Added", type: .recent, items: recent))
                } else {
                    let fallback = repo.getRecentFallback(type: typeStr, limit: 20)
                    if !fallback.isEmpty {
                        newSections.append(HomeSection(title: "New Arrivals", type: .recent, items: fallback))
                    }
                }
                
                // 5. Smart Genres & Fallback
                if let pl = selectedPlaylist {
                    let allGroups = repo.getGroups(playlistUrl: pl.url, type: selectedTab)
                    
                    let premiumKeywords = ["Netflix", "Disney", "Apple", "Amazon", "Hulu", "HBO", "4K", "UHD"]
                    let standardKeywords = ["Action", "Comedy", "Drama", "Sci-Fi", "Horror", "Documentary", "Kids", "Family", "Thriller", "Adventure", "Animation", "Crime", "Mystery"]
                    
                    var addedGroups = Set<String>()
                    
                    // A. Premium Providers (Top Priority)
                    for group in allGroups {
                        if premiumKeywords.contains(where: { group.localizedCaseInsensitiveContains($0) }) {
                            let items = repo.getByGenre(type: typeStr, groupName: group, limit: 20)
                            if !items.isEmpty && !addedGroups.contains(group) {
                                newSections.append(HomeSection(title: group, type: .provider(group), items: items))
                                addedGroups.insert(group)
                            }
                        }
                    }
                    
                    // B. Standard Genres
                    for group in allGroups {
                        if standardKeywords.contains(where: { group.localizedCaseInsensitiveContains($0) }) {
                            let items = repo.getByGenre(type: typeStr, groupName: group, limit: 20)
                            if !items.isEmpty && !addedGroups.contains(group) {
                                newSections.append(HomeSection(title: group, type: .genre(group), items: items))
                                addedGroups.insert(group)
                            }
                        }
                    }
                    
                    // C. Fallback: If we don't have enough rows, just add whatever groups we have!
                    // This ensures the screen isn't empty if the provider uses weird names.
                    if newSections.count < 6 {
                        for group in allGroups {
                            if !addedGroups.contains(group) {
                                let items = repo.getByGenre(type: typeStr, groupName: group, limit: 20)
                                if !items.isEmpty {
                                    newSections.append(HomeSection(title: group, type: .genre(group), items: items))
                                    addedGroups.insert(group)
                                }
                                if newSections.count >= 15 { break } // Hard limit
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.sections = newSections
                self.isLoading = false
                self.updateGreeting() // Refresh greeting after load
            }
        }
    }
    
    // MARK: - Helper: Fetch Trending
    
    private func fetchTrendingItems(type: StreamType) async -> [Channel] {
        guard let repo = repository else { return [] }
        do {
            // 1. Get Global Trends from TMDB
            let tmdbResults = try await tmdbClient.getTrending(type: type.rawValue)
            
            // 2. Extract Titles/Names
            let titles = tmdbResults.map { $0.displayTitle }
            
            // 3. Find matches in our local Xtream database
            return repo.getTrendingMatches(type: type.rawValue, tmdbResults: titles)
        } catch {
            print("Trending Fetch Failed: \(error)")
            return []
        }
    }
    
    // MARK: - Drill Down Logic
    
    func openCategory(_ section: HomeSection) {
        guard let repo = repository, let pl = selectedPlaylist else { return }
        let type = selectedTab.rawValue
        
        switch section.type {
        case .genre(let g), .provider(let g):
            self.drillDownCategory = g
            self.displayedGridChannels = repo.getBrowsingContent(playlistUrl: pl.url, type: type, group: g)
            
        case .recent:
            self.drillDownCategory = "Recently Added"
            self.displayedGridChannels = repo.getRecentFallback(type: type, limit: 200)
            
        case .favorites:
            self.drillDownCategory = "My List"
            self.displayedGridChannels = repo.getFavorites(type: type)
            
        case .continueWatching:
            self.drillDownCategory = "Continue Watching"
            self.displayedGridChannels = section.items
            
        case .trending:
            self.drillDownCategory = "Trending Now"
            self.displayedGridChannels = section.items
        }
    }
    
    func closeDrillDown() {
        self.drillDownCategory = nil
    }
}
