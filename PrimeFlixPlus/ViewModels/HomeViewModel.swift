import Foundation
import CoreData
import Combine
import SwiftUI

struct HomeSection: Identifiable {
    // We use a combination of Title + Type to ensure uniqueness if two categories clean to the same name
    var id: String { "\(title)_\(type)" }
    let title: String
    let type: SectionType
    let items: [Channel]
    
    enum SectionType: Hashable {
        case continueWatching
        case favorites
        case trending
        case recent
        case recommended
        case genre(String)   // Stores the RAW group name (e.g. "NL | Disney")
        case provider(String)
        
        func hash(into hasher: inout Hasher) {
            switch self {
            case .genre(let g): hasher.combine("genre"); hasher.combine(g)
            case .provider(let p): hasher.combine("provider"); hasher.combine(p)
            case .continueWatching: hasher.combine("cw")
            case .favorites: hasher.combine("fav")
            case .trending: hasher.combine("tr")
            case .recent: hasher.combine("rc")
            case .recommended: hasher.combine("rec")
            }
        }
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
    
    // Access User Preferences
    @AppStorage("preferredLanguage") var preferredLanguage: String = "English"
    
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
        
        // Initial load of cached data
        refreshContent(forceLoadingState: sections.isEmpty)
        
        // 1. Listen specifically for Sync Status changes to auto-refresh when sync completes
        repository.$isSyncing
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isSyncing in
                guard let self = self else { return }
                
                if !isSyncing {
                    // Sync just finished. Now it is safe to refresh the UI once.
                    print("🔄 Sync finished. Refreshing Home UI.")
                    // Add a small delay to ensure Core Data context is fully merged
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        self.refreshContent(forceLoadingState: false)
                    }
                } else {
                    // Sync started. Do nothing. Let the user browse cached data undisturbed.
                    print("⏳ Sync started. Pausing UI updates.")
                }
            }
            .store(in: &cancellables)
        
        // 2. Listen for Category/Settings Changes (Auto-refresh on Hide/Unhide/Auto-Hide)
        NotificationCenter.default.publisher(for: CategoryPreferences.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                print("🔄 Categories changed. Refreshing Home UI immediately.")
                self?.refreshContent(forceLoadingState: false)
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
        let userLang = self.preferredLanguage
        
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
            var trendingIDs: [NSManagedObjectID] = []
            if !trendingTitles.isEmpty {
                trendingIDs = await repo.getTrendingMatchesAsync(type: typeStr, tmdbResults: trendingTitles)
            }
            
            // 2. Build Sections (Main Actor)
            await MainActor.run {
                var newSections: [HomeSection] = []
                
                // --- 1. Standard Lanes ---
                
                // Continue Watching
                let resumeItems = repo.getSmartContinueWatching(type: typeStr)
                if !resumeItems.isEmpty {
                    newSections.append(HomeSection(title: "Continue Watching", type: .continueWatching, items: resumeItems))
                }
                
                // Recommended For You
                let recs = repo.getRecommended(type: typeStr)
                if !recs.isEmpty {
                    newSections.append(HomeSection(title: "Recommended For You", type: .recommended, items: recs))
                }
                
                // Trending
                if !trendingIDs.isEmpty {
                    let context = repo.container.viewContext
                    let trendingMatches = trendingIDs.compactMap { try? context.existingObject(with: $0) as? Channel }
                    
                    if !trendingMatches.isEmpty {
                        newSections.append(HomeSection(title: "Trending Now", type: .trending, items: trendingMatches))
                    }
                }
                
                // Favorites
                let favs = repo.getFavorites(type: typeStr)
                if !favs.isEmpty {
                    newSections.append(HomeSection(title: "My List", type: .favorites, items: favs))
                }
                
                // Recent (Only for VOD)
                if currentTab != .live {
                    let recent = repo.getRecentlyAdded(type: typeStr, limit: 20)
                    if !recent.isEmpty {
                        newSections.append(HomeSection(title: "Recently Added", type: .recent, items: recent))
                    }
                }
                
                // --- 2. Smart Category Lanes ---
                
                if let pl = currentPlaylist {
                    let allGroups = repo.getGroups(playlistUrl: pl.url, type: currentTab)
                    var addedGroups = Set<String>()
                    
                    // Smart Keywords for type detection (styling)
                    let premiumKeywords = ["Netflix", "Disney", "Pixar", "Marvel", "Apple", "Amazon", "Hulu", "HBO", "4K", "UHD"]
                    
                    // Consolidated Loop: Filter, Clean, and Add
                    for rawGroup in allGroups {
                        // A. FILTER: Check against User Language & Hidden Categories (using SettingsViewModel logic)
                        if !CategoryPreferences.shared.shouldShow(group: rawGroup, language: userLang) {
                            continue
                        }
                        
                        // B. CLEAN: Remove prefixes like "NL | "
                        let cleanTitle = CategoryPreferences.shared.cleanName(rawGroup)
                        
                        // C. DEDUP: Skip if we already added this RAW group or a cleaned version of it
                        if addedGroups.contains(rawGroup) { continue }
                        
                        // D. FETCH CONTENT
                        let items = repo.getByGenre(type: typeStr, groupName: rawGroup, limit: 20)
                        
                        if !items.isEmpty {
                            // Determine type for potential UI styling
                            let isPremium = premiumKeywords.contains { rawGroup.localizedCaseInsensitiveContains($0) }
                            let type: HomeSection.SectionType = isPremium ? .provider(rawGroup) : .genre(rawGroup)
                            
                            newSections.append(HomeSection(title: cleanTitle, type: type, items: items))
                            addedGroups.insert(rawGroup)
                        }
                        
                        // E. LIMIT: Prevent infinite scrolling performance issues
                        if newSections.count >= 20 { break }
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
        
        // Fetch content for the "See All" grid
        Task {
            let results: [Channel]
            
            switch section.type {
            case .genre(let rawGroup), .provider(let rawGroup):
                self.drillDownCategory = section.title // Show Clean Title in Header
                // Use Raw Group ID/Name to fetch content
                results = repo.getBrowsingContent(playlistUrl: pl.url, type: type, group: rawGroup)
                
            case .recent:
                self.drillDownCategory = "Recently Added"
                results = repo.getRecentFallback(type: type, limit: 200)
                
            case .favorites:
                self.drillDownCategory = "My List"
                results = repo.getFavorites(type: type)
                
            case .continueWatching:
                self.drillDownCategory = "Continue Watching"
                results = section.items
                
            case .trending:
                self.drillDownCategory = "Trending Now"
                results = section.items
                
            case .recommended:
                self.drillDownCategory = "Recommended For You"
                results = repo.getRecommended(type: type)
            }
            
            // Update UI on MainActor
            await MainActor.run {
                self.displayedGridChannels = results
            }
        }
    }
    
    func closeDrillDown() {
        self.drillDownCategory = nil
    }
}
