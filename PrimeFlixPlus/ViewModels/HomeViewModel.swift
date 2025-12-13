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
        case tasteBreakers // New Logic
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
    @Published var isLoading: Bool = true
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
        
        if selectedPlaylist == nil, let first = playlists.first {
            self.selectedPlaylist = first
        }
        
        updateGreeting()
        setupListeners()
        
        if selectedPlaylist != nil {
            loadTab(selectedTab)
        }
        
        startContentWatchdog()
    }
    
    private func setupListeners() {
        guard let repository = repository else { return }
        
        // Playlist Updates
        repository.objectWillChange
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.playlists = repository.getAllPlaylists()
                if self.selectedPlaylist == nil, let first = self.playlists.first {
                    self.selectedPlaylist = first
                    self.loadTab(self.selectedTab)
                }
            }
            .store(in: &cancellables)
        
        // Sync Completion
        repository.$isSyncing
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isSyncing in
                if !isSyncing { self?.invalidateCache() }
            }
            .store(in: &cancellables)
            
        // Preferences
        NotificationCenter.default.publisher(for: CategoryPreferences.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.invalidateCache() }
            .store(in: &cancellables)
    }
    
    func selectPlaylist(_ playlist: Playlist) {
        self.selectedPlaylist = playlist
        updateGreeting()
        invalidateCache()
    }
    
    // MARK: - Watchdog
    
    private func startContentWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // If screen is blank but we have a playlist, force reload
                if self.sections.isEmpty && self.selectedPlaylist != nil && !self.isLoading {
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
        tabCache = [.movie: HomeTabState(), .series: HomeTabState(), .live: HomeTabState()]
        loadTab(selectedTab)
    }
    
    // MARK: - Core Logic
    
    private func loadTab(_ tab: StreamType) {
        guard let repo = repository, let pl = selectedPlaylist else {
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
            
            // 1. Network Fetch (Trending)
            var trendingTitles: [String] = []
            if tab != .live {
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
                let recService = RecommendationService(context: context)
                let readRepo = ChannelRepository(context: context)
                let prefsRepo = UserPreferencesRepository(container: repo.container)
                
                // A. Continue Watching
                let resume = readRepo.getSmartContinueWatching(type: type)
                if !resume.isEmpty {
                    initialSections.append(HomeSection(title: "Continue Watching", type: .continueWatching, items: resume))
                }
                
                // B. Fresh For You (Sequels / New Seasons)
                if tab != .live {
                    let fresh = recService.getFreshFranchiseContent(type: type)
                    if !fresh.isEmpty {
                        initialSections.append(HomeSection(title: "Fresh For You", type: .freshContent, items: fresh))
                    }
                }
                
                // C. Trending (TMDB Mapping)
                if !trendingTitles.isEmpty {
                    let trending = recService.getTrendingMatches(type: type, tmdbResults: trendingTitles)
                    if !trending.isEmpty {
                        initialSections.append(HomeSection(title: "Trending Now", type: .trending, items: trending))
                    }
                }
                
                // D. Recommended (Based on Genres/History)
                if tab != .live {
                    let recommended = recService.getRecommended(type: type)
                    if !recommended.isEmpty {
                        initialSections.append(HomeSection(title: "Recommended", type: .recommended, items: recommended))
                    }
                }
                
                // E. Taste Breakers (NEW Logic)
                if tab != .live {
                    let profile = prefsRepo.getProfile()
                    let userGenres = Set((profile.selectedGenres ?? "").components(separatedBy: ","))
                    
                    let tasteBreakers = self.fetchTasteBreakers(
                        context: context,
                        type: type,
                        avoidGenres: userGenres
                    )
                    if !tasteBreakers.isEmpty {
                        initialSections.append(HomeSection(title: "Taste Breakers", type: .tasteBreakers, items: tasteBreakers))
                    }
                }
                
                // F. Recently Added (Fallback)
                if tab != .live {
                    let recent = readRepo.getRecentlyAdded(type: type, limit: 20)
                    if !recent.isEmpty {
                        initialSections.append(HomeSection(title: "Recently Added", type: .recent, items: recent))
                    }
                }
                
                // G. Groups (For "View All Categories")
                allGroups = readRepo.getGroups(playlistUrl: playlistUrl, type: type)
            }
            
            if Task.isCancelled { return }
            
            self.finalizeInitialLoad(tab: tab, sections: initialSections, allGroups: allGroups, lang: lang)
        }
    }
    
    // MARK: - Taste Breakers Logic
    
    private func fetchTasteBreakers(context: NSManagedObjectContext, type: String, avoidGenres: Set<String>) -> [Channel] {
        // 1. Identify "Breaker" Categories (Groups that don't match user prefs)
        let groupReq = NSFetchRequest<NSDictionary>(entityName: "Channel")
        groupReq.resultType = .dictionaryResultType
        groupReq.propertiesToFetch = ["group"]
        groupReq.returnsDistinctResults = true
        groupReq.predicate = NSPredicate(format: "type == %@", type)
        
        guard let results = try? context.fetch(groupReq) as? [[String: String]] else { return [] }
        let allGroups = results.compactMap { $0["group"] }
        
        // Find groups that do NOT contain any of the user's preferred genre strings
        let candidateGroups = allGroups.filter { group in
            !avoidGenres.contains { group.localizedCaseInsensitiveContains($0) }
        }
        
        if candidateGroups.isEmpty { return [] }
        
        // 2. Fetch random highly-rated items from these groups
        // We use "4K" or "UHD" as a proxy for high quality since external ratings might be sparse initially
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        let groupsToCheck = Array(candidateGroups.prefix(10)) // Limit check to 10 random groups for speed
        
        req.predicate = NSPredicate(
            format: "type == %@ AND group IN %@ AND (quality CONTAINS[cd] '4K' OR quality CONTAINS[cd] 'UHD' OR quality CONTAINS[cd] '1080')",
            type, groupsToCheck
        )
        req.fetchLimit = 50
        req.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        
        guard let items = try? context.fetch(req) else { return [] }
        
        // Shuffle in memory to ensure variety
        return Array(items.shuffled().prefix(15))
    }
    
    // MARK: - Finalization
    
    private func finalizeInitialLoad(tab: StreamType, sections: [HomeSection], allGroups: [String], lang: String) {
        let cleanGroups = allGroups.filter { CategoryPreferences.shared.shouldShow(group: $0, language: lang) }
        
        var state = self.tabCache[tab] ?? HomeTabState()
        state.sections = sections
        state.allGroupNames = cleanGroups
        state.loadedGroupIndex = 0
        state.hasLoadedInitial = true
        self.tabCache[tab] = state
        
        if self.selectedTab == tab {
            withAnimation {
                self.sections = sections
                self.isLoading = false
            }
            // Trigger loading of standard genres after main content is ready
            self.loadMoreGenres()
        }
    }
    
    // MARK: - Lazy Loading Groups
    
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
        guard var currentState = self.tabCache[self.selectedTab] else { return }
        
        currentState.sections.append(contentsOf: newSections)
        currentState.loadedGroupIndex = newIndex
        self.tabCache[self.selectedTab] = currentState
        
        withAnimation { self.sections.append(contentsOf: newSections) }
        self.isLoadingMore = false
        
        if self.sections.count < 4 && newIndex < currentState.allGroupNames.count {
            self.loadMoreGenres()
        }
    }
    
    // MARK: - UI Helpers
    
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
            self.drillDownCategory = "Fresh For You"
            self.displayedGridChannels = section.items
            return
        }
        if case .tasteBreakers = section.type {
            self.drillDownCategory = "Taste Breakers"
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
