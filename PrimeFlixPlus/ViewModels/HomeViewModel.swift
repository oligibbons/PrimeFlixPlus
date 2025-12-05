import Foundation
import CoreData
import Combine
import SwiftUI

// MARK: - Data Models

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
        case freshContent // New Type for "Your Fresh Content"
        case genre(String)
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
            case .freshContent: hasher.combine("fresh")
            }
        }
    }
}

// MARK: - Tab State Container
/// Caches the state of a specific tab so switching back is instant.
struct HomeTabState {
    var sections: [HomeSection] = []
    var allGroupNames: [String] = [] // All available categories, not yet loaded
    var loadedGroupIndex: Int = 0    // Pointer for pagination
    var hasLoadedInitial: Bool = false
}

@MainActor
class HomeViewModel: ObservableObject {
    
    // --- Navigation & State ---
    @Published var selectedTab: StreamType = .movie
    @Published var selectedPlaylist: Playlist?
    
    // The "Rails" for the Home Screen (Driven by current tab)
    @Published var sections: [HomeSection] = []
    
    // UI State
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false // For bottom pagination spinner
    
    // Greetings
    @Published var timeGreeting: String = "Welcome Back"
    @Published var witGreeting: String = "Ready to watch?"
    
    // Drill Down State
    @Published var drillDownCategory: String? = nil
    @Published var displayedGridChannels: [Channel] = []
    
    // --- Internal Caching ---
    // We keep a separate state for each tab to allow instant switching
    private var tabCache: [StreamType: HomeTabState] = [
        .movie: HomeTabState(),
        .series: HomeTabState(),
        .live: HomeTabState()
    ]
    
    // --- Preferences ---
    @AppStorage("preferredLanguage") var preferredLanguage: String = "English"
    
    // --- Dependencies ---
    private var repository: PrimeFlixRepository?
    private let tmdbClient = TmdbClient()
    private var cancellables = Set<AnyCancellable>()
    
    // Task management for cancellation
    private var currentFetchTask: Task<Void, Never>?
    
    // MARK: - Setup
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.playlists = repository.getAllPlaylists()
        
        if selectedPlaylist == nil, let first = playlists.first {
            selectedPlaylist = first
        }
        
        updateGreeting()
        
        // Initial Load
        loadTab(selectedTab)
        
        // Listen for Sync completion to clear cache and refresh
        repository.$isSyncing
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isSyncing in
                guard let self = self else { return }
                if !isSyncing {
                    // Sync complete: invalidate cache and reload current tab
                    self.invalidateCache()
                }
            }
            .store(in: &cancellables)
        
        // Listen for Settings changes (Hidden Categories)
        NotificationCenter.default.publisher(for: CategoryPreferences.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.invalidateCache()
            }
            .store(in: &cancellables)
    }
    
    @Published var playlists: [Playlist] = []
    
    func selectPlaylist(_ playlist: Playlist) {
        self.selectedPlaylist = playlist
        updateGreeting()
        invalidateCache() // Playlist changed, data is invalid
    }
    
    // MARK: - Tab Management (The Smart Part)
    
    func selectTab(_ tab: StreamType) {
        guard tab != selectedTab else { return }
        
        // 1. Cancel any ongoing fetch for the previous tab
        currentFetchTask?.cancel()
        
        self.selectedTab = tab
        
        // 2. Instant Cache Restore
        if tabCache[tab]?.hasLoadedInitial == true {
            self.sections = tabCache[tab]?.sections ?? []
            self.isLoading = false
        } else {
            // 3. Cold Start for this tab
            self.sections = []
            self.isLoading = true
            loadTab(tab)
        }
    }
    
    private func invalidateCache() {
        // Reset all caches
        tabCache = [
            .movie: HomeTabState(),
            .series: HomeTabState(),
            .live: HomeTabState()
        ]
        // Reload current
        loadTab(selectedTab)
    }
    
    // MARK: - Phase 1: Initial Load (Critical Lanes)
    
    private func loadTab(_ tab: StreamType) {
        guard let repo = repository else { return }
        
        // Cancel previous task to prevent race conditions
        currentFetchTask?.cancel()
        
        self.isLoading = true
        let playlistUrl = selectedPlaylist?.url ?? ""
        let lang = preferredLanguage
        
        currentFetchTask = Task {
            // A. Fetch "Fast" Data (Favorites, History, Recent)
            // We run this on a background context
            let context = repo.container.newBackgroundContext()
            
            // 1. Fetch Trending IDs (Network call - might be slow, so we allow it to fail/timeout gently)
            var trendingIDs: [NSManagedObjectID] = []
            if tab != .live {
                let titles = (try? await tmdbClient.getTrending(type: tab.rawValue))?.map { $0.displayTitle } ?? []
                if !titles.isEmpty {
                    trendingIDs = await repo.getTrendingMatchesAsync(type: tab.rawValue, tmdbResults: titles)
                }
            }
            
            if Task.isCancelled { return }
            
            // 2. Build Critical Sections
            var initialSections: [HomeSection] = []
            var allGroups: [String] = []
            
            await context.perform {
                let readRepo = ChannelRepository(context: context)
                
                // 1. Continue Watching (Priority #1)
                let resume = readRepo.getSmartContinueWatching(type: tab.rawValue)
                if !resume.isEmpty {
                    initialSections.append(HomeSection(title: "Continue Watching", type: .continueWatching, items: resume))
                }
                
                // 2. Your Fresh Content (Priority #2 - NEW)
                if tab != .live {
                    let fresh = readRepo.getFreshFranchiseContent(type: tab.rawValue)
                    if !fresh.isEmpty {
                        initialSections.append(HomeSection(title: "Your Fresh Content", type: .freshContent, items: fresh))
                    }
                }
                
                // 3. Trending Now
                if !trendingIDs.isEmpty {
                    let trending = trendingIDs.compactMap { try? context.existingObject(with: $0) as? Channel }
                    if !trending.isEmpty {
                        initialSections.append(HomeSection(title: "Trending Now", type: .trending, items: trending))
                    }
                }
                
                // 4. Favorites
                let favs = readRepo.getFavorites(type: tab.rawValue)
                if !favs.isEmpty {
                    initialSections.append(HomeSection(title: "My List", type: .favorites, items: favs))
                }
                
                // 5. Recommended For You (Filtered by Locale)
                if tab != .live {
                    let recommended = readRepo.getRecommended(type: tab.rawValue)
                    if !recommended.isEmpty {
                        initialSections.append(HomeSection(title: "Recommended For You", type: .recommended, items: recommended))
                    }
                }
                
                // 6. Recently Added
                if tab != .live {
                    let recent = readRepo.getRecentlyAdded(type: tab.rawValue, limit: 20)
                    if !recent.isEmpty {
                        initialSections.append(HomeSection(title: "Recently Added", type: .recent, items: recent))
                    }
                }
                
                // 7. Fetch ALL Group Names (Lightweight) to prepare for Pagination
                allGroups = readRepo.getGroups(playlistUrl: playlistUrl, type: tab.rawValue)
            }
            
            if Task.isCancelled { return }
            
            // 4. Update Main Actor (Render Initial View)
            // No await needed here because we are already on MainActor due to Task
            self.finalizeInitialLoad(tab: tab, sections: initialSections, allGroups: allGroups, lang: lang)
        }
    }
    
    // Helper to update state safely on MainActor
    private func finalizeInitialLoad(tab: StreamType, sections: [HomeSection], allGroups: [String], lang: String) {
        // Apply sorting/filtering to groups
        let cleanGroups = allGroups.filter {
            CategoryPreferences.shared.shouldShow(group: $0, language: lang)
        }
        
        // Update Cache State
        var state = self.tabCache[tab] ?? HomeTabState()
        state.sections = sections
        state.allGroupNames = cleanGroups
        state.loadedGroupIndex = 0
        state.hasLoadedInitial = true
        self.tabCache[tab] = state
        
        // Update UI if this is still the active tab
        if self.selectedTab == tab {
            self.sections = sections
            self.isLoading = false
            // Immediately trigger the first batch of genres
            self.loadMoreGenres()
        }
    }
    
    // MARK: - Phase 2: Lazy Pagination (Genres)
    
    func loadMoreGenres() {
        guard let repo = repository, !isLoadingMore else { return }
        
        // Use 'let' to snapshot state
        let state = tabCache[selectedTab] ?? HomeTabState()
        
        // Check if we have more groups to load
        guard state.loadedGroupIndex < state.allGroupNames.count else { return }
        
        self.isLoadingMore = true
        let type = selectedTab.rawValue
        
        // Determine batch range (Load 5 categories at a time)
        let startIndex = state.loadedGroupIndex
        let endIndex = min(startIndex + 5, state.allGroupNames.count)
        let groupsToLoad = Array(state.allGroupNames[startIndex..<endIndex])
        
        Task {
            let context = repo.container.newBackgroundContext()
            var newSections: [HomeSection] = []
            
            await context.perform {
                let readRepo = ChannelRepository(context: context)
                
                for rawGroup in groupsToLoad {
                    let items = readRepo.getByGenre(type: type, groupName: rawGroup, limit: 15)
                    
                    if !items.isEmpty {
                        let cleanTitle = CategoryPreferences.shared.cleanName(rawGroup)
                        
                        let isPremium = ["Netflix", "Disney", "Pixar", "Marvel", "Apple", "HBO", "4K"].contains { rawGroup.localizedCaseInsensitiveContains($0) }
                        let sectionType: HomeSection.SectionType = isPremium ? .provider(rawGroup) : .genre(rawGroup)
                        
                        newSections.append(HomeSection(title: cleanTitle, type: sectionType, items: items))
                    }
                }
            }
            
            if Task.isCancelled { return }
            
            // No await needed here because we are already on MainActor due to Task
            self.finalizeMoreGenres(newSections: newSections, newIndex: endIndex)
        }
    }
    
    // Helper to update state safely on MainActor
    private func finalizeMoreGenres(newSections: [HomeSection], newIndex: Int) {
        // 1. Update Cache
        var currentState = self.tabCache[self.selectedTab]!
        currentState.sections.append(contentsOf: newSections)
        currentState.loadedGroupIndex = newIndex
        self.tabCache[self.selectedTab] = currentState
        
        // 2. Update UI (Append)
        withAnimation {
            self.sections.append(contentsOf: newSections)
        }
        
        self.isLoadingMore = false
        
        // Optimization: Keep loading if screen is empty
        if self.sections.count < 4 && newIndex < currentState.allGroupNames.count {
            self.loadMoreGenres()
        }
    }
    
    // MARK: - Drill Down & UI Helpers
    
    private func updateGreeting() {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 { self.timeGreeting = "Up late?" }
        else if hour < 12 { self.timeGreeting = "Good Morning" }
        else if hour < 17 { self.timeGreeting = "Good Afternoon" }
        else { self.timeGreeting = "Good Evening" }
        
        let playfulMessages = [
            "Popcorn ready?", "Let's find something amazing.", "Cinema mode: On.",
            "Your library looks great.", "Time to relax.", "Discover something new."
        ]
        
        if playlists.isEmpty { self.witGreeting = "Let's get you set up." }
        else { self.witGreeting = playfulMessages.randomElement() ?? "Ready to watch?" }
    }
    
    func openCategory(_ section: HomeSection) {
        guard let repo = repository, let pl = selectedPlaylist else { return }
        let type = selectedTab.rawValue
        
        Task {
            let results: [Channel]
            
            switch section.type {
            case .genre(let rawGroup), .provider(let rawGroup):
                self.drillDownCategory = section.title
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
                self.drillDownCategory = "Recommended"
                results = repo.getRecommended(type: type)
            case .freshContent:
                self.drillDownCategory = "Your Fresh Content"
                results = section.items
            }
            
            await MainActor.run {
                self.displayedGridChannels = results
            }
        }
    }
    
    func closeDrillDown() {
        self.drillDownCategory = nil
    }
}
