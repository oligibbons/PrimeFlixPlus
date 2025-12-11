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
    
    // MARK: - Session Persistence (Static)
    // Preserves state when navigating away (Details) and back (re-init)
    struct SearchSession {
        let query: String
        let scope: SearchScope
        let movieIDs: [NSManagedObjectID]
        let seriesIDs: [NSManagedObjectID]
        let liveCats: [String]
        let liveChanIDs: [NSManagedObjectID]
    }
    
    private static var lastSession: SearchSession?
    
    // MARK: - Initialization
    init(initialScope: SearchScope = .library) {
        self.searchHistory = UserDefaults.standard.stringArray(forKey: "SearchHistory") ?? []
        
        // Restore Session if available
        if let session = SearchViewModel.lastSession {
            self.query = session.query
            self.selectedScope = session.scope
            // Objects are re-fetched in configure() to ensure context safety
        } else {
            self.selectedScope = initialScope
        }
    }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        
        // Re-hydrate objects if we restored a session
        if let session = SearchViewModel.lastSession, !session.query.isEmpty {
            let context = repository.container.viewContext
            
            if session.scope == .library {
                self.movies = session.movieIDs.compactMap { try? context.existingObject(with: $0) as? Channel }
                self.series = session.seriesIDs.compactMap { try? context.existingObject(with: $0) as? Channel }
            } else {
                self.liveCategories = session.liveCats
                self.liveChannels = session.liveChanIDs.compactMap { try? context.existingObject(with: $0) as? Channel }
            }
        }
        
        setupSubscriptions()
    }
    
    // MARK: - History Management
    
    func addToHistory(_ term: String) {
        guard !term.isEmpty else { return }
        if let index = searchHistory.firstIndex(of: term) {
            searchHistory.remove(at: index)
        }
        searchHistory.insert(term, at: 0)
        if searchHistory.count > 10 { searchHistory.removeLast() }
        UserDefaults.standard.set(searchHistory, forKey: "SearchHistory")
    }
    
    func clearHistory() {
        searchHistory.removeAll()
        UserDefaults.standard.set(searchHistory, forKey: "SearchHistory")
    }
    
    // MARK: - Search Logic
    
    private func setupSubscriptions() {
        // 1. Watch Query
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newQuery in
                guard let self = self else { return }
                if !newQuery.isEmpty {
                    self.performSearch()
                } else if newQuery.isEmpty && !self.movies.isEmpty {
                    // Only clear if explicitly empty, not just init
                    self.clearResults()
                }
            }
            .store(in: &cancellables)
        
        // 2. Watch Scope
        $selectedScope
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
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
        searchTask?.cancel()
        
        let currentQuery = query
        let currentScope = selectedScope
        
        searchTask = Task {
            let bgContext = repo.container.newBackgroundContext()
            
            await bgContext.perform { [weak self] in
                guard let self = self else { return }
                let searchRepo = ChannelRepository(context: bgContext)
                
                if currentScope == .library {
                    // Use deduplicated logic from Repository
                    let results = searchRepo.searchLibrary(query: currentQuery)
                    
                    let movieIDs = results.movies.map { $0.objectID }
                    let seriesIDs = results.series.map { $0.objectID }
                    
                    Task { @MainActor in
                        if Task.isCancelled { return }
                        
                        let viewContext = repo.container.viewContext
                        self.movies = movieIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                        self.series = seriesIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                        
                        self.finalizeSearch(scope: .library, mIDs: movieIDs, sIDs: seriesIDs)
                        
                        // Background Enrichment
                        if !self.movies.isEmpty || !self.series.isEmpty {
                            let combined = Array((self.movies + self.series).prefix(8))
                            await repo.enrichContent(items: combined)
                        }
                    }
                    
                } else {
                    // Live TV
                    let results = searchRepo.searchLive(query: currentQuery)
                    let chanIDs = results.channels.map { $0.objectID }
                    
                    Task { @MainActor in
                        if Task.isCancelled { return }
                        
                        let viewContext = repo.container.viewContext
                        self.liveCategories = results.categories
                        self.liveChannels = chanIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                        
                        self.finalizeSearch(scope: .liveTV, liveCats: results.categories, liveIDs: chanIDs)
                    }
                }
            }
        }
    }
    
    private func finalizeSearch(scope: SearchScope, mIDs: [NSManagedObjectID] = [], sIDs: [NSManagedObjectID] = [], liveCats: [String] = [], liveIDs: [NSManagedObjectID] = []) {
        self.isLoading = false
        
        if scope == .library {
            self.hasNoResults = self.movies.isEmpty && self.series.isEmpty
        } else {
            self.hasNoResults = self.liveCategories.isEmpty && self.liveChannels.isEmpty
        }
        
        // Save Session
        SearchViewModel.lastSession = SearchSession(
            query: self.query,
            scope: self.selectedScope,
            movieIDs: mIDs,
            seriesIDs: sIDs,
            liveCats: liveCats,
            liveChanIDs: liveIDs
        )
    }
    
    func clearResults() {
        self.movies = []
        self.series = []
        self.liveCategories = []
        self.liveChannels = []
        self.isLoading = false
        self.hasNoResults = false
        
        SearchViewModel.lastSession = nil
    }
    
    // MARK: - Actions
    
    func refineSearch(to category: String) {
        self.query = category
    }
}
