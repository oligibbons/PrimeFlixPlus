// oligibbons/primeflixplus/PrimeFlixPlus-87ed36e89476dd94828b2fb759896cdbd9a22d84/PrimeFlixPlus/ViewModels/HomeViewModel.swift

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
        case freshContent // "Your Fresh Content"
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
        
        // Setup live updates for content, preferences, and language
        setupListeners()
    }
    
    private func setupListeners() {
        guard let repository = repository else { return }
        
        // 1. Sync completion (Full Refresh)
        // This handles the moment "Enrichment" finishes.
        repository.$isSyncing
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isSyncing in
                guard let self = self else { return }
                if !isSyncing {
                    print("🔄 HomeViewModel: Sync/Enrichment complete. Refreshing view.")
                    self.invalidateCache()
                }
            }
            .store(in: &cancellables)
        
        // 2. Repository Updates (Content/Favorites/Progress)
        // UPGRADE: We now allow refreshes even during syncing if it's a "minor" update,
        // but we debounce heavily to prevent UI stutter during the massive Poster Enrichment phase.
        repository.objectWillChange
            .debounce(for: .seconds(2), scheduler: RunLoop.main) // Increased debounce to 2s to batch poster updates
            .sink { [weak self] _ in
                guard let self = self else { return }
                // We refresh even if syncing, but the debounce protects us from 2000 refreshes.
                print("🔄 HomeViewModel: Detected data change, refreshing...")
                self.invalidateCache()
            }
            .store(in: &cancellables)
        
        // 3. Settings changes (Hidden Categories)
        NotificationCenter.default.publisher(for: CategoryPreferences.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                print("⚙️ HomeViewModel: Category preferences changed, refreshing...")
                self?.invalidateCache()
            }
            .store(in: &cancellables)
        
        // 4. Language Changes (UserDefaults)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .compactMap { _ in UserDefaults.standard.string(forKey: "preferredLanguage") }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] newLang in
                print("🌍 HomeViewModel: Language changed to \(newLang), refreshing...")
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
    
    // MARK: - Tab Management
    
    func selectTab(_ tab: StreamType) {
        guard tab != selectedTab else { return }
        
        currentFetchTask?.cancel()
        self.selectedTab = tab
        
        if tabCache[tab]?.hasLoadedInitial == true {
            self.sections = tabCache[tab]?.sections ?? []
            self.isLoading = false
        } else {
            self.sections = []
            self.isLoading = true
            loadTab(tab)
        }
    }
    
    private func invalidateCache() {
        // Clear all caches to force fresh fetch from Core Data (picking up new Covers)
        tabCache = [
            .movie: HomeTabState(),
            .series: HomeTabState(),
            .live: HomeTabState()
        ]
        loadTab(selectedTab)
    }
    
    // MARK: - Phase 1: Initial Load (Critical Lanes)
    
    private func loadTab(_ tab: StreamType) {
        guard let repo = repository else { return }
        
        currentFetchTask?.cancel()
        
        self.isLoading = true
        let playlistUrl = selectedPlaylist?.url ?? ""
        let lang = preferredLanguage
        
        currentFetchTask = Task {
            let context = repo.container.newBackgroundContext()
            
            // 1. Fetch Trending IDs (Network)
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
                
                // A. Continue Watching
                let resume = readRepo.getSmartContinueWatching(type: tab.rawValue)
                if !resume.isEmpty {
                    initialSections.append(HomeSection(title: "Continue Watching", type: .continueWatching, items: resume))
                }
                
                // B. Your Fresh Content (New Seasons/Sequels)
                if tab != .live {
                    let fresh = readRepo.getFreshFranchiseContent(type: tab.rawValue)
                    if !fresh.isEmpty {
                        initialSections.append(HomeSection(title: "Your Fresh Content", type: .freshContent, items: fresh))
                    }
                }
                
                // C. Trending Now (Mapped from API)
                if !trendingIDs.isEmpty {
                    let trending = trendingIDs.compactMap { try? context.existingObject(with: $0) as? Channel }
                    if !trending.isEmpty {
                        initialSections.append(HomeSection(title: "Trending Now", type: .trending, items: trending))
                    }
                }
                
                // D. Favorites
                let favs = readRepo.getFavorites(type: tab.rawValue)
                if !favs.isEmpty {
                    initialSections.append(HomeSection(title: "My List", type: .favorites, items: favs))
                }
                
                // E. Recommended
                if tab != .live {
                    let recommended = readRepo.getRecommended(type: tab.rawValue)
                    if !recommended.isEmpty {
                        initialSections.append(HomeSection(title: "Recommended For You", type: .recommended, items: recommended))
                    }
                }
                
                // F. Recently Added
                if tab != .live {
                    let recent = readRepo.getRecentlyAdded(type: tab.rawValue, limit: 20)
                    if !recent.isEmpty {
                        initialSections.append(HomeSection(title: "Recently Added", type: .recent, items: recent))
                    }
                }
                
                // G. Fetch Groups for Pagination
                allGroups = readRepo.getGroups(playlistUrl: playlistUrl, type: tab.rawValue)
            }
            
            if Task.isCancelled { return }
            
            self.finalizeInitialLoad(tab: tab, sections: initialSections, allGroups: allGroups, lang: lang)
        }
    }
    
    private func finalizeInitialLoad(tab: StreamType, sections: [HomeSection], allGroups: [String], lang: String) {
        let cleanGroups = allGroups.filter {
            CategoryPreferences.shared.shouldShow(group: $0, language: lang)
        }
        
        var state = self.tabCache[tab] ?? HomeTabState()
        state.sections = sections
        state.allGroupNames = cleanGroups
        state.loadedGroupIndex = 0
        state.hasLoadedInitial = true
        self.tabCache[tab] = state
        
        if self.selectedTab == tab {
            self.sections = sections
            self.isLoading = false
            self.loadMoreGenres()
        }
    }
    
    // MARK: - Phase 2: Lazy Pagination
    
    func loadMoreGenres() {
        guard let repo = repository, !isLoadingMore else { return }
        
        let state = tabCache[selectedTab] ?? HomeTabState()
        guard state.loadedGroupIndex < state.allGroupNames.count else { return }
        
        self.isLoadingMore = true
        let type = selectedTab.rawValue
        
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
            self.finalizeMoreGenres(newSections: newSections, newIndex: endIndex)
        }
    }
    
    private func finalizeMoreGenres(newSections: [HomeSection], newIndex: Int) {
        var currentState = self.tabCache[self.selectedTab]!
        currentState.sections.append(contentsOf: newSections)
        currentState.loadedGroupIndex = newIndex
        self.tabCache[self.selectedTab] = currentState
        
        withAnimation {
            self.sections.append(contentsOf: newSections)
        }
        
        self.isLoadingMore = false
        
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
