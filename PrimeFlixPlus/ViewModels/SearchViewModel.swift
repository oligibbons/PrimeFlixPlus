import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class SearchViewModel: ObservableObject {
    
    // MARK: - Search Scopes
    enum SearchScope: String, CaseIterable {
        case library = "Library"
        case liveTV = "Live TV"
    }
    
    // MARK: - Inputs
    @Published var query: String = ""
    @Published var selectedScope: SearchScope = .library
    
    // MARK: - Outputs (Library)
    @Published var movies: [Channel] = []
    @Published var series: [Channel] = []
    
    // MARK: - Outputs (Live TV)
    @Published var liveCategories: [String] = []
    @Published var liveChannels: [Channel] = []
    
    // MARK: - UI State
    @Published var isLoading: Bool = false
    @Published var hasNoResults: Bool = false
    
    // MARK: - History
    @Published var searchHistory: [String] = []
    
    // MARK: - Dependencies
    private var repository: PrimeFlixRepository?
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Initialization
    init(initialScope: SearchScope = .library) {
        self.selectedScope = initialScope
        self.searchHistory = UserDefaults.standard.stringArray(forKey: "SearchHistory") ?? []
    }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        setupSubscriptions()
    }
    
    // MARK: - History Management
    
    func addToHistory(_ term: String) {
        guard !term.isEmpty else { return }
        // Remove duplicate if exists, then prepend
        if let index = searchHistory.firstIndex(of: term) {
            searchHistory.remove(at: index)
        }
        searchHistory.insert(term, at: 0)
        
        // Cap at 10 items
        if searchHistory.count > 10 {
            searchHistory.removeLast()
        }
        UserDefaults.standard.set(searchHistory, forKey: "SearchHistory")
    }
    
    func clearHistory() {
        searchHistory.removeAll()
        UserDefaults.standard.set(searchHistory, forKey: "SearchHistory")
    }
    
    // MARK: - Search Logic
    
    private func setupSubscriptions() {
        // 1. Watch Query (Debounced)
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newQuery in
                guard let self = self else { return }
                if !newQuery.isEmpty {
                    self.performSearch()
                } else {
                    self.clearResults()
                }
            }
            .store(in: &cancellables)
        
        // 2. Watch Scope (Immediate)
        $selectedScope
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // If query exists, re-run search immediately for new scope
                if !self.query.isEmpty {
                    self.performSearch()
                } else {
                    self.clearResults()
                }
            }
            .store(in: &cancellables)
    }
    
    func performSearch() {
        guard let repo = repository, !query.isEmpty else {
            clearResults()
            return
        }
        
        self.isLoading = true
        self.hasNoResults = false
        
        // Cancel any existing task
        searchTask?.cancel()
        
        let currentQuery = query
        let currentScope = selectedScope
        
        searchTask = Task {
            // Perform heavy lifting on background context
            let bgContext = repo.container.newBackgroundContext()
            
            await bgContext.perform { [weak self] in
                guard let self = self else { return }
                
                let searchRepo = ChannelRepository(context: bgContext)
                
                if currentScope == .library {
                    // --- LIBRARY SEARCH ---
                    // FIX: Calls the dedicated 'searchLibrary' method we restored
                    let results = searchRepo.searchLibrary(query: currentQuery)
                    
                    // Map to ObjectIDs for thread transfer
                    let movieIDs = results.movies.map { $0.objectID }
                    let seriesIDs = results.series.map { $0.objectID }
                    
                    Task { @MainActor in
                        if Task.isCancelled { return }
                        
                        let viewContext = repo.container.viewContext
                        // Re-fetch objects on Main Thread
                        self.movies = movieIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                        self.series = seriesIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                        
                        self.isLoading = false
                        self.hasNoResults = self.movies.isEmpty && self.series.isEmpty
                        
                        // Trigger Enrichment (optional, for missing covers)
                        if !self.movies.isEmpty || !self.series.isEmpty {
                            let combined = Array((self.movies + self.series).prefix(8))
                            await repo.enrichContent(items: combined)
                        }
                    }
                    
                } else {
                    // --- LIVE TV SEARCH ---
                    // FIX: Calls 'searchLive' (renamed from searchLiveContent to match repo)
                    let results = searchRepo.searchLive(query: currentQuery)
                    
                    let channelIDs = results.channels.map { $0.objectID }
                    let foundCategories = results.categories
                    
                    Task { @MainActor in
                        if Task.isCancelled { return }
                        
                        let viewContext = repo.container.viewContext
                        self.liveCategories = foundCategories
                        self.liveChannels = channelIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                        
                        self.isLoading = false
                        self.hasNoResults = self.liveCategories.isEmpty && self.liveChannels.isEmpty
                    }
                }
            }
        }
    }
    
    func clearResults() {
        self.movies = []
        self.series = []
        self.liveCategories = []
        self.liveChannels = []
        self.isLoading = false
        self.hasNoResults = false
    }
    
    // MARK: - Actions
    
    /// Allows clicking a category in search results to refine the search to that category name
    func refineSearch(to category: String) {
        self.query = category
        // The subscription to $query will pick this up and trigger a search automatically
    }
}
