import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class SearchViewModel: ObservableObject {
    
    // MARK: - Search Scopes
    enum SearchScope: String, CaseIterable {
        case all = "All"
        case movies = "Movies"
        case series = "Series"
        case live = "Live TV"
    }
    
    // MARK: - Inputs
    @Published var query: String = ""
    @Published var selectedScope: SearchScope = .all
    
    // MARK: - Outputs
    @Published var movies: [Channel] = []
    @Published var series: [Channel] = []
    @Published var liveChannels: [Channel] = []
    
    // Smart Collections (The "Reverse Search" Result)
    @Published var personMatch: TmdbPersonResult? = nil
    @Published var personCredits: [Channel] = [] // e.g. "Tom Cruise Movies" available locally
    
    // History
    @Published var searchHistory: [String] = []
    
    // MARK: - UI State
    @Published var isLoading: Bool = false
    @Published var hasNoResults: Bool = false
    @Published var activeFilters: ChannelRepository.SearchFilters = .init()
    
    // MARK: - Dependencies
    private var repository: PrimeFlixRepository?
    private let tmdbClient = TmdbClient()
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Initialization
    init() {
        loadHistory()
        setupSubscriptions()
    }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
    }
    
    private func setupSubscriptions() {
        // 1. Debounced Search Trigger
        // We wait 0.8s after typing stops to protect API limits and reduce database thrashing
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .sink { [weak self] newQuery in
                self?.handleQueryChange(newQuery)
            }
            .store(in: &cancellables)
        
        // 2. Scope/Filter Trigger (Immediate)
        $selectedScope
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.triggerImmediateSearch()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Search Orchestration
    
    private func handleQueryChange(_ newQuery: String) {
        if newQuery.isEmpty {
            clearResults()
            return
        }
        
        // Cancel any pending task (Fast Typing)
        searchTask?.cancel()
        
        searchTask = Task {
            await performHybridSearch(query: newQuery)
        }
    }
    
    private func triggerImmediateSearch() {
        let currentQuery = query
        guard !currentQuery.isEmpty else { return }
        
        searchTask?.cancel()
        searchTask = Task {
            await performHybridSearch(query: currentQuery)
        }
    }
    
    private func performHybridSearch(query: String) async {
        guard let repo = repository else { return }
        
        self.isLoading = true
        self.hasNoResults = false
        self.personMatch = nil
        self.personCredits = []
        
        // Map UI Scope to Repository Filters
        var filters = ChannelRepository.SearchFilters()
        switch selectedScope {
        case .movies: filters.onlyMovies = true
        case .series: filters.onlySeries = true
        case .live: filters.onlyLive = true
        case .all: break
        }
        
        // --- PARALLEL EXECUTION START ---
        
        // Task A: Local Hybrid Search (Fuzzy Matching)
        // Runs on background thread via Repository
        async let localResults = Task.detached(priority: .userInitiated) {
            return await repo.searchHybrid(query: query, filters: filters)
        }.value
        
        // Task B: Remote Person Search (API)
        // Only run if scope allows (not Live TV) and query is long enough
        let shouldSearchPeople = (selectedScope != .live) && (query.count > 3)
        
        async let remotePerson: TmdbPersonResult? = shouldSearchPeople ? findBestPersonMatch(query: query) : nil
        
        // --- AWAIT RESULTS ---
        
        let (local, person) = await (localResults, remotePerson)
        
        // --- SYNTHESIS ---
        
        // If we found a person, fetch their credits and cross-reference locally
        var creditsFound: [Channel] = []
        if let person = person {
            creditsFound = await resolvePersonCredits(personId: person.id, repo: repo)
        }
        
        // Update UI on Main Actor
        if !Task.isCancelled {
            withAnimation(.easeInOut) {
                self.movies = local.movies
                self.series = local.series
                self.liveChannels = local.live
                
                self.personMatch = person
                self.personCredits = creditsFound
                
                let totalCount = local.movies.count + local.series.count + local.live.count + creditsFound.count
                self.hasNoResults = (totalCount == 0)
                self.isLoading = false
            }
            
            // Auto-save history if successful search
            if !hasNoResults {
                addToHistory(query)
            }
        }
    }
    
    // MARK: - Reverse Search Logic
    
    private func findBestPersonMatch(query: String) async -> TmdbPersonResult? {
        // We only want the top result to keep the UI clean
        // e.g. "Tom Cru" -> "Tom Cruise"
        do {
            let results = try await tmdbClient.searchPerson(query: query)
            return results.first
        } catch {
            print("Person Search Error: \(error)")
            return nil
        }
    }
    
    private func resolvePersonCredits(personId: Int, repo: PrimeFlixRepository) async -> [Channel] {
        do {
            let credits = try await tmdbClient.getPersonCredits(personId: personId)
            
            // Extract titles from Cast (and high-profile Crew jobs if needed)
            // Filter by popularity to prioritize famous works
            let candidateTitles = credits.cast
                .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                .prefix(50) // Limit to top 50 works to prevent massive DB query
                .map { $0.displayTitle }
            
            // Cross-reference with Local DB
            // We need a thread-safe way to call the repository's batch lookup
            // Since repo methods are now MainActor (or context-bound), we use the repo's context wrapper logic.
            // Note: In Step 2, we added `findMatches` to ChannelRepository.
            // We need to access the underlying ChannelRepository instance safely.
            // Since PrimeFlixRepository wraps it, we'll add a passthrough or use the bg context pattern.
            
            // Using a detached task with a new context to perform the read safely
            return await Task.detached {
                let bgContext = repo.container.newBackgroundContext()
                let readRepo = ChannelRepository(context: bgContext)
                return readRepo.findMatches(for: Array(candidateTitles))
            }.value
            
        } catch {
            print("Credit Resolution Error: \(error)")
            return []
        }
    }
    
    // MARK: - History Management
    
    private let historyKey = "user_search_history"
    
    func loadHistory() {
        self.searchHistory = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }
    
    func addToHistory(_ term: String) {
        let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        var current = searchHistory
        if let existingIndex = current.firstIndex(of: clean) {
            current.remove(at: existingIndex)
        }
        current.insert(clean, at: 0)
        
        // Cap at 10 items
        if current.count > 10 {
            current = Array(current.prefix(10))
        }
        
        searchHistory = current
        UserDefaults.standard.set(current, forKey: historyKey)
    }
    
    func clearHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
    
    // MARK: - UI Helpers
    
    func selectHistoryItem(_ term: String) {
        self.query = term
        // The subscription will handle the search triggering
    }
    
    func clearResults() {
        self.movies = []
        self.series = []
        self.liveChannels = []
        self.personMatch = nil
        self.personCredits = []
        self.hasNoResults = false
        self.isLoading = false
    }
}

// MARK: - Repository Extension
// Helper to bridge the new repo method if it wasn't exposed in PrimeFlixRepository
extension PrimeFlixRepository {
    // We need to expose the internal container to allow the ViewModel to create background contexts
    // (This is already public in the original file, just ensuring visibility for the detached task above)
}
