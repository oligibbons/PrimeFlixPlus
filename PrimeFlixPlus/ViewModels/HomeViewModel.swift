import Foundation
import CoreData
import Combine
import SwiftUI

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
        case genre(String)
        case provider(String)
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
    
    // Drill Down
    @Published var drillDownCategory: String? = nil
    @Published var displayedGridChannels: [Channel] = []
    
    // Greetings
    @Published var timeGreeting: String = "Welcome Back"
    @Published var witGreeting: String = "Ready to watch?"
    
    private var repository: PrimeFlixRepository?
    private let tmdbClient = TmdbClient()
    private var cancellables = Set<AnyCancellable>()
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.playlists = repository.getAllPlaylists()
        
        if selectedPlaylist == nil, let first = playlists.first {
            selectedPlaylist = first
        }
        
        updateGreeting()
        
        // Initial load
        refreshContent(forceLoadingState: sections.isEmpty)
        
        // Listen for repository changes (Background Sync completion)
        repository.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    self?.refreshContent(forceLoadingState: false)
                }
            }
            .store(in: &cancellables)
    }
    
    func selectPlaylist(_ playlist: Playlist) {
        self.selectedPlaylist = playlist
        updateGreeting()
        refreshContent(forceLoadingState: true)
    }
    
    func selectTab(_ tab: StreamType) {
        self.selectedTab = tab
        self.drillDownCategory = nil
        refreshContent(forceLoadingState: false)
    }
    
    private func updateGreeting() {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 { self.timeGreeting = "Up late?" }
        else if hour < 12 { self.timeGreeting = "Good Morning" }
        else if hour < 17 { self.timeGreeting = "Good Afternoon" }
        else { self.timeGreeting = "Good Evening" }
        
        let playfulMessages = [
            "Popcorn ready?", "Let's find something amazing.", "Cinema mode: On.",
            "Your library looks great.", "Time to relax.", "Ready for the next episode?",
            "The show must go on.", "Discover something new.", "It's movie night.",
            "Press play and drift away."
        ]
        
        if playlists.isEmpty { self.witGreeting = "Let's get you set up." }
        else if sections.isEmpty { self.witGreeting = "Building your cinema..." }
        else { self.witGreeting = playfulMessages.randomElement() ?? "Ready to watch?" }
    }
    
    // MARK: - Main Refresh Logic
    
    func refreshContent(forceLoadingState: Bool = false) {
        guard let repo = repository else { return }
        
        if forceLoadingState {
            self.isLoading = true
            self.sections = []
        }
        
        let currentTab = selectedTab
        let currentPlaylist = selectedPlaylist
        let client = self.tmdbClient
        let typeStr = currentTab.rawValue
        
        // Run network logic in background task
        Task {
            // 1. Fetch Trending Titles (Background)
            var trendingTitles: [String] = []
            if currentTab != .live {
                do {
                    // TMDB network call - slow, so keep it off main thread
                    let results = try await client.getTrending(type: typeStr)
                    trendingTitles = results.map { $0.displayTitle }
                } catch {
                    print("Trending fetch error: \(error)")
                }
            }
            
            // 1.5 Fetch Trending IDs (Background - Performance Optimization)
            // Heavy string matching happens here off the main thread
            var trendingIDs: [NSManagedObjectID] = []
            if !trendingTitles.isEmpty {
                trendingIDs = await repo.getTrendingMatchesAsync(type: typeStr, tmdbResults: trendingTitles)
            }
            
            // 2. Build Sections (Main Actor)
            await MainActor.run {
                var newSections: [HomeSection] = []
                
                // --- LIVE TV ---
                if currentTab == .live {
                    let favs = repo.getFavorites(type: typeStr)
                    if !favs.isEmpty {
                        newSections.append(HomeSection(title: "Favorite Channels", type: .favorites, items: favs))
                    }
                    
                    let recent = repo.getSmartContinueWatching(type: typeStr)
                    if !recent.isEmpty {
                        newSections.append(HomeSection(title: "Recently Watched", type: .continueWatching, items: recent))
                    }
                    
                    if let pl = currentPlaylist {
                        let allGroups = repo.getGroups(playlistUrl: pl.url, type: currentTab)
                        for group in allGroups {
                            let items = repo.getByGenre(type: typeStr, groupName: group, limit: 20)
                            if !items.isEmpty {
                                newSections.append(HomeSection(title: group, type: .genre(group), items: items))
                            }
                        }
                    }
                    
                } else {
                    // --- MOVIES & SERIES ---
                    
                    // 1. Continue Watching
                    let resumeItems = repo.getSmartContinueWatching(type: typeStr)
                    if !resumeItems.isEmpty {
                        newSections.append(HomeSection(title: "Continue Watching", type: .continueWatching, items: resumeItems))
                    }
                    
                    // 2. Trending (Optimized)
                    if !trendingIDs.isEmpty {
                        // Rapidly resolve objects on Main Context using IDs found in background
                        let context = repo.container.viewContext
                        let trendingMatches = trendingIDs.compactMap { try? context.existingObject(with: $0) as? Channel }
                        
                        if !trendingMatches.isEmpty {
                            newSections.append(HomeSection(title: "Trending Now", type: .trending, items: trendingMatches))
                        }
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
                    
                    // 5. Providers & Genres
                    if let pl = currentPlaylist {
                        let allGroups = repo.getGroups(playlistUrl: pl.url, type: currentTab)
                        
                        let premiumKeywords = ["Netflix", "Disney", "Apple", "Amazon", "Hulu", "HBO", "4K", "UHD"]
                        let standardKeywords = ["Action", "Comedy", "Drama", "Sci-Fi", "Horror", "Documentary", "Kids", "Family", "Thriller", "Adventure"]
                        var addedGroups = Set<String>()
                        
                        // Providers
                        for group in allGroups {
                            if premiumKeywords.contains(where: { group.localizedCaseInsensitiveContains($0) }) {
                                let items = repo.getByGenre(type: typeStr, groupName: group, limit: 20)
                                if !items.isEmpty && !addedGroups.contains(group) {
                                    newSections.append(HomeSection(title: group, type: .provider(group), items: items))
                                    addedGroups.insert(group)
                                }
                            }
                        }
                        
                        // Genres
                        for group in allGroups {
                            if standardKeywords.contains(where: { group.localizedCaseInsensitiveContains($0) }) {
                                let items = repo.getByGenre(type: typeStr, groupName: group, limit: 20)
                                if !items.isEmpty && !addedGroups.contains(group) {
                                    newSections.append(HomeSection(title: group, type: .genre(group), items: items))
                                    addedGroups.insert(group)
                                }
                            }
                        }
                        
                        // Fallback (Fill space)
                        if newSections.count < 6 {
                            for group in allGroups {
                                if !addedGroups.contains(group) {
                                    let items = repo.getByGenre(type: typeStr, groupName: group, limit: 20)
                                    if !items.isEmpty {
                                        newSections.append(HomeSection(title: group, type: .genre(group), items: items))
                                        addedGroups.insert(group)
                                    }
                                    if newSections.count >= 15 { break }
                                }
                            }
                        }
                    }
                }
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.sections = newSections
                    self.isLoading = false
                    self.updateGreeting()
                }
            }
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
