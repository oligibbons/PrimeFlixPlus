import Foundation
import CoreData
import Combine
import SwiftUI

// MARK: - Data Models

struct HomeSection: Identifiable {
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
        case freshContent
        case genre(String)
        case provider(String)
    }
}

struct HomeTabState {
    var sections: [HomeSection] = []
    var allGroupNames: [String] = []
    var loadedGroupIndex: Int = 0
    var hasLoadedInitial: Bool = false
}

@MainActor
class HomeViewModel: ObservableObject {
    
    // --- Navigation & State ---
    @Published var selectedTab: StreamType = .movie
    @Published var selectedPlaylist: Playlist?
    @Published var playlists: [Playlist] = []
    @Published var sections: [HomeSection] = []
    @Published var isLoading: Bool = true // Start true to show spinner immediately
    @Published var isLoadingMore: Bool = false
    
    // Greetings
    @Published var timeGreeting: String = ""
    @Published var witGreeting: String = ""
    
    // Drill Down
    @Published var drillDownCategory: String? = nil
    @Published var displayedGridChannels: [Channel] = []
    
    // --- Preferences ---
    @AppStorage("preferredLanguage") var preferredLanguage: String = "English"
    
    // --- Internal ---
    private var tabCache: [StreamType: HomeTabState] = [
        .movie: HomeTabState(), .series: HomeTabState(), .live: HomeTabState()
    ]
    private var repository: PrimeFlixRepository?
    private let tmdbClient = TmdbClient()
    private var cancellables = Set<AnyCancellable>()
    private var currentFetchTask: Task<Void, Never>?
    private var watchdogTimer: Timer?
    
    // MARK: - Setup
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.playlists = repository.getAllPlaylists()
        
        // 1. Immediate Playlist Selection
        if selectedPlaylist == nil {
            if let first = playlists.first {
                self.selectedPlaylist = first
            }
        }
        
        updateGreeting()
        setupListeners()
        
        // 2. Initial Load
        // If we have a playlist, load immediately.
        // If not, the listener below will trigger it when data arrives.
        if selectedPlaylist != nil {
            loadTab(selectedTab)
        }
        
        startContentWatchdog()
    }
    
    private func setupListeners() {
        guard let repository = repository else { return }
        
        // A. Watch for Playlist Updates (Fix for "Blank on First Launch")
        repository.objectWillChange
            .sink { [weak self] _ in
                guard let self = self else { return }
                let freshPlaylists = repository.getAllPlaylists()
                self.playlists = freshPlaylists
                
                // If we didn't have a playlist before, select one now and load
                if self.selectedPlaylist == nil, let first = freshPlaylists.first {
                    self.selectedPlaylist = first
                    self.updateGreeting()
                    self.loadTab(self.selectedTab)
                }
            }
            .store(in: &cancellables)
        
        // B. Sync Completion (Refetch Data)
        repository.$isSyncing
            .dropFirst() // Ignore initial state
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isSyncing in
                // When sync finishes (goes to false), force reload
                if !isSyncing {
                    self?.invalidateCache()
                }
            }
            .store(in: &cancellables)
        
        // C. Settings/Language Changes
        NotificationCenter.default.publisher(for: CategoryPreferences.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.invalidateCache() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .compactMap { _ in UserDefaults.standard.string(forKey: "preferredLanguage") }
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.invalidateCache() }
            .store(in: &cancellables)
    }
    
    func selectPlaylist(_ playlist: Playlist) {
        self.selectedPlaylist = playlist
        updateGreeting()
        invalidateCache()
    }
    
    // MARK: - Safety Mechanisms
    
    /// Watchdog: If the screen remains blank for 5 seconds, force a reload.
    /// This fixes race conditions where the view might load before Core Data is ready.
    private func startContentWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.sections.isEmpty && self.selectedPlaylist != nil {
                    print("⚠️ [HomeViewModel] Watchdog triggered reload.")
                    self.invalidateCache()
                }
            }
        }
    }
    
    // MARK: - Tab Logic
    
    func selectTab(_ tab: StreamType) {
        guard tab != selectedTab else { return }
        currentFetchTask?.cancel()
        self.selectedTab = tab
        
        // Use Cache if valid
        if let state = tabCache[tab], state.hasLoadedInitial, !state.sections.isEmpty {
            self.sections = state.sections
            self.isLoading = false
        } else {
            self.sections = []
            self.isLoading = true
            loadTab(tab)
        }
    }
    
    private func invalidateCache() {
        // Clear everything to force fresh fetch from Core Data
        tabCache = [.movie: HomeTabState(), .series: HomeTabState(), .live: HomeTabState()]
        loadTab(selectedTab)
    }
    
    // MARK: - Core Logic
    
    private func loadTab(_ tab: StreamType) {
        guard let repo = repository else { return }
        
        // Ensure we actually have a source
        guard let pl = selectedPlaylist else {
            self.isLoading = false
            return
        }
        
        currentFetchTask?.cancel()
        self.isLoading = true
        
        let playlistUrl = pl.url
        let lang = preferredLanguage
        let type = tab.rawValue
        
        currentFetchTask = Task {
            let context = repo.container.newBackgroundContext()
            
            // 1. Fetch Trending from API first (Network)
            var trendingTitles: [String] = []
            if tab != .live {
                // We wrap this in do-catch so network failure doesn't kill the whole load
                do {
                    let trending = try await tmdbClient.getTrending(type: type)
                    trendingTitles = trending.map { $0.displayTitle }
                } catch {
                    print("⚠️ Trending Fetch Failed: \(error.localizedDescription)")
                }
            }
            
            if Task.isCancelled { return }
            
            // 2. Build Sections (Background Context)
            var initialSections: [HomeSection] = []
            var allGroups: [String] = []
            
            await context.perform {
                // Initialize Services
                let recService = RecommendationService(context: context)
                let readRepo = ChannelRepository(context: context)
                
                // A. Continue Watching (Basic)
                let resume = readRepo.getSmartContinueWatching(type: type)
                if !resume.isEmpty {
                    initialSections.append(HomeSection(title: "Continue Watching", type: .continueWatching, items: resume))
                }
                
                // B. Fresh Content (Smart Service)
                if tab != .live {
                    let fresh = recService.getFreshFranchiseContent(type: type)
                    if !fresh.isEmpty {
                        initialSections.append(HomeSection(title: "Your Fresh Content", type: .freshContent, items: fresh))
                    }
                }
                
                // C. Trending (Smart Service)
                if !trendingTitles.isEmpty {
                    let trending = recService.getTrendingMatches(type: type, tmdbResults: trendingTitles)
                    if !trending.isEmpty {
                        initialSections.append(HomeSection(title: "Trending Now", type: .trending, items: trending))
                    }
                }
                
                // D. Favorites (Basic)
                let favs = readRepo.getFavorites(type: type)
                if !favs.isEmpty {
                    initialSections.append(HomeSection(title: "My List", type: .favorites, items: favs))
                }
                
                // E. Recommended (Smart Service)
                if tab != .live {
                    let recommended = recService.getRecommended(type: type)
                    if !recommended.isEmpty {
                        initialSections.append(HomeSection(title: "Recommended For You", type: .recommended, items: recommended))
                    }
                }
                
                // F. Recently Added (Basic)
                if tab != .live {
                    let recent = readRepo.getRecentlyAdded(type: type, limit: 20)
                    if !recent.isEmpty {
                        initialSections.append(HomeSection(title: "Recently Added", type: .recent, items: recent))
                    }
                }
                
                // G. Groups
                allGroups = readRepo.getGroups(playlistUrl: playlistUrl, type: type)
            }
            
            if Task.isCancelled { return }
            
            self.finalizeInitialLoad(tab: tab, sections: initialSections, allGroups: allGroups, lang: lang)
        }
    }
    
    private func finalizeInitialLoad(tab: StreamType, sections: [HomeSection], allGroups: [String], lang: String) {
        let cleanGroups = allGroups.filter { CategoryPreferences.shared.shouldShow(group: $0, language: lang) }
        
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
                        // Heuristic for "Provider" lanes
                        let isPremium = ["Netflix", "HBO", "Apple", "Disney"].contains { rawGroup.localizedCaseInsensitiveContains($0) }
                        newSections.append(HomeSection(title: cleanTitle, type: isPremium ? .provider(rawGroup) : .genre(rawGroup), items: items))
                    }
                }
            }
            
            await MainActor.run {
                self.finalizeMoreGenres(newSections: newSections, newIndex: endIndex)
            }
        }
    }
    
    private func finalizeMoreGenres(newSections: [HomeSection], newIndex: Int) {
        // Safety check if tab changed while loading
        guard var currentState = self.tabCache[self.selectedTab] else { return }
        
        currentState.sections.append(contentsOf: newSections)
        currentState.loadedGroupIndex = newIndex
        self.tabCache[self.selectedTab] = currentState
        
        withAnimation { self.sections.append(contentsOf: newSections) }
        self.isLoadingMore = false
        
        // Recursive load if screen is still empty (e.g., all 5 groups were empty)
        if self.sections.count < 4 && newIndex < currentState.allGroupNames.count {
            self.loadMoreGenres()
        }
    }
    
    // MARK: - UI Logic
    
    private func updateGreeting() {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 { self.timeGreeting = "Up late?" }
        else if hour < 12 { self.timeGreeting = "Good Morning" }
        else if hour < 17 { self.timeGreeting = "Good Afternoon" }
        else { self.timeGreeting = "Good Evening" }
        
        if playlists.isEmpty { self.witGreeting = "Let's get you set up." }
        else { self.witGreeting = "Ready to watch?" }
    }
    
    func openCategory(_ section: HomeSection) {
        guard let repo = repository, let pl = selectedPlaylist else { return }
        let type = selectedTab.rawValue
        
        // Instant load for sections that already have items
        if case .trending = section.type {
            self.drillDownCategory = "Trending Now"
            self.displayedGridChannels = section.items
            return
        }
        if case .continueWatching = section.type {
            self.drillDownCategory = "Continue Watching"
            self.displayedGridChannels = section.items
            return
        }
        if case .freshContent = section.type {
            self.drillDownCategory = "Your Fresh Content"
            self.displayedGridChannels = section.items
            return
        }
        
        // Fetch for others
        Task {
            let results: [Channel]
            switch section.type {
            case .genre(let g), .provider(let g):
                self.drillDownCategory = section.title
                results = repo.getBrowsingContent(playlistUrl: pl.url, type: type, group: g)
            case .recent:
                self.drillDownCategory = "Recently Added"
                results = repo.getRecentFallback(type: type, limit: 200)
            case .favorites:
                self.drillDownCategory = "My List"
                results = repo.getFavorites(type: type)
            case .recommended:
                self.drillDownCategory = "Recommended"
                results = repo.getRecommended(type: type)
            default: results = []
            }
            
            await MainActor.run { self.displayedGridChannels = results }
        }
    }
    
    func closeDrillDown() {
        self.drillDownCategory = nil
    }
}
