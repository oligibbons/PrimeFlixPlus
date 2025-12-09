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
    @Published var personCredits: [Channel] = []
    
    // History
    @Published var searchHistory: [String] = []
    
    // Filters (Must be exposed for SearchFilterBar)
    @Published var activeFilters: ChannelRepository.SearchFilters = .init()
    
    // MARK: - UI State
    @Published var isLoading: Bool = false
    @Published var hasNoResults: Bool = false
    
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
        // Wait 0.6s to avoid hammering the DB while typing
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] newQuery in
                self?.handleQueryChange(newQuery)
            }
            .store(in: &cancellables)
        
        // 2. Scope Change (Immediate)
        $selectedScope
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.triggerImmediateSearch()
            }
            .store(in: &cancellables)
            
        // 3. Filter Change (Immediate)
        $activeFilters
            .dropFirst() // Skip initial value
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                if !(self?.query.isEmpty ?? true) {
                    self?.triggerImmediateSearch()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    internal func triggerImmediateSearch() {
        let currentQuery = query
        guard !currentQuery.isEmpty || activeFilters.hasActiveFilters else { return }
        
        searchTask?.cancel()
        searchTask = Task {
            await performHybridSearch(query: currentQuery)
        }
    }
    
    private func handleQueryChange(_ newQuery: String) {
        if newQuery.isEmpty {
            clearResults()
            return
        }
        
        searchTask?.cancel()
        searchTask = Task {
            await performHybridSearch(query: newQuery)
        }
    }
    
    private func performHybridSearch(query: String) async {
        guard let repo = repository else { return }
        
        self.isLoading = true
        self.hasNoResults = false
        self.personMatch = nil
        self.personCredits = []
        
        // 1. Prepare Filters
        var filters = activeFilters
        switch selectedScope {
        case .movies: filters.onlyMovies = true
        case .series: filters.onlySeries = true
        case .live: filters.onlyLive = true
        case .all: break
        }
        
        // Capture for async closure
        let searchFilters = filters

        // --- PARALLEL EXECUTION ---
        
        // Task A: Local Database Search (The "Hybrid" Logic)
        async let localResults = repo.searchHybrid(query: query, filters: searchFilters)
        
        // Task B: Remote Person Search (API)
        // Only run if scope allows and query is substantial
        let shouldSearchPeople = (selectedScope != .live) && (query.count > 2)
        async let remotePerson: TmdbPersonResult? = shouldSearchPeople ? findBestPersonMatch(query: query) : nil
        
        // --- AWAIT & PROCESS ---
        
        let (local, person) = await (localResults, remotePerson)
        
        // If we found a person, fetch their filmography and check our DB
        var creditsFound: [Channel] = []
        if let person = person {
            creditsFound = await resolvePersonCredits(personId: person.id, repo: repo)
        }
        
        // Update UI
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
            
            if !hasNoResults {
                addToHistory(query)
                
                // --- CRITICAL FIX: Trigger Image Enrichment ---
                // We collect all the results we just found and ask the Repo to fetch covers for them immediately.
                // This ensures that "Unknown" images get fixed right before the user's eyes.
                let allItems = local.movies + local.series + creditsFound
                if !allItems.isEmpty {
                    Task.detached(priority: .background) {
                        await repo.enrichContent(items: allItems)
                    }
                }
            }
        }
    }
    
    // MARK: - Person Logic
    
    private func findBestPersonMatch(query: String) async -> TmdbPersonResult? {
        do {
            let results = try await tmdbClient.searchPerson(query: query)
            // Return the first valid person
            return results.first
        } catch {
            return nil
        }
    }
    
    private func resolvePersonCredits(personId: Int, repo: PrimeFlixRepository) async -> [Channel] {
        do {
            let credits = try await tmdbClient.getPersonCredits(personId: personId)
            
            // Extract titles from Cast/Crew, prioritized by popularity
            let candidateTitles = credits.cast
                .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                .prefix(50)
                .map { $0.displayTitle }
            
            // Cross-reference with Local DB using the new efficient finder
            return await repo.findMatches(for: Array(candidateTitles))
            
        } catch {
            return []
        }
    }
    
    // MARK: - History
    
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
    
    // MARK: - Helpers
    
    func selectHistoryItem(_ term: String) {
        self.query = term
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
