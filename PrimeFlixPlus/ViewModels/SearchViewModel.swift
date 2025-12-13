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
    
    // MARK: - Session Persistence
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
        
        if let session = SearchViewModel.lastSession {
            self.query = session.query
            self.selectedScope = session.scope
        } else {
            self.selectedScope = initialScope
        }
    }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        
        // Restore objects if session exists
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
    
    // MARK: - History
    func addToHistory(_ term: String) {
        guard !term.isEmpty else { return }
        if let index = searchHistory.firstIndex(of: term) { searchHistory.remove(at: index) }
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
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newQuery in
                if !newQuery.isEmpty { self?.performSearch() }
                else if newQuery.isEmpty && !(self?.movies.isEmpty ?? true) { self?.clearResults() }
            }
            .store(in: &cancellables)
        
        $selectedScope
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if !self.query.isEmpty { self.performSearch() } else { self.clearResults() }
            }
            .store(in: &cancellables)
    }
    
    func performSearch() {
        guard let repo = repository, !query.isEmpty else { clearResults(); return }
        
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
                    let rawResults = searchRepo.searchLibrary(query: currentQuery)
                    
                    // --- DEDUPLICATION LOGIC ---
                    let uniqueMovies = self.deduplicateResults(rawResults.movies)
                    let uniqueSeries = self.deduplicateResults(rawResults.series)
                    
                    let movieIDs = uniqueMovies.map { $0.objectID }
                    let seriesIDs = uniqueSeries.map { $0.objectID }
                    
                    Task { @MainActor in
                        if Task.isCancelled { return }
                        let viewContext = repo.container.viewContext
                        self.movies = movieIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                        self.series = seriesIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                        
                        self.finalizeSearch(scope: .library, mIDs: movieIDs, sIDs: seriesIDs)
                        
                        // Background Enrichment for top results
                        if !self.movies.isEmpty || !self.series.isEmpty {
                            let combined = Array((self.movies + self.series).prefix(8))
                            await repo.enrichContent(items: combined)
                        }
                    }
                    
                } else {
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
    
    // MARK: - Smart Deduplication
    
    /// Groups channels by their NORMALIZED title and picks the best one.
    /// This collapses "Severance 4K", "Severance HD", "Severance (2022)" into one entry.
    private func deduplicateResults(_ items: [Channel]) -> [Channel] {
        var grouped: [String: [Channel]] = [:]
        
        for item in items {
            let info = TitleNormalizer.parse(rawTitle: item.canonicalTitle ?? item.title)
            grouped[info.normalizedTitle, default: []].append(item)
        }
        
        // For each group, pick the "Best" candidate to display
        // Priority: 1. Has Cover Art -> 2. Is 4K/UHD -> 3. Is NOT an episode (if series search)
        return grouped.values.compactMap { candidates -> Channel? in
            return candidates.sorted { c1, c2 in
                // 1. Prefer Cover
                let c1HasCover = (c1.cover != nil)
                let c2HasCover = (c2.cover != nil)
                if c1HasCover != c2HasCover { return c1HasCover }
                
                // 2. Prefer Series Container over Episode
                if c1.type != c2.type {
                    if c1.type == "series" { return true }
                    if c2.type == "series" { return false }
                }
                
                // 3. Prefer Higher Quality (Lexical check)
                let q1 = c1.quality ?? ""
                let q2 = c2.quality ?? ""
                if q1.contains("4K") && !q2.contains("4K") { return true }
                if q2.contains("4K") && !q1.contains("4K") { return false }
                
                return false // Keep original order if equal
            }.first
        }.sorted { $0.title < $1.title }
    }
    
    private func finalizeSearch(scope: SearchScope, mIDs: [NSManagedObjectID] = [], sIDs: [NSManagedObjectID] = [], liveCats: [String] = [], liveIDs: [NSManagedObjectID] = []) {
        self.isLoading = false
        if scope == .library {
            self.hasNoResults = self.movies.isEmpty && self.series.isEmpty
        } else {
            self.hasNoResults = self.liveCategories.isEmpty && self.liveChannels.isEmpty
        }
        
        SearchViewModel.lastSession = SearchSession(
            query: self.query, scope: self.selectedScope,
            movieIDs: mIDs, seriesIDs: sIDs,
            liveCats: liveCats, liveChanIDs: liveIDs
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
    
    func refineSearch(to category: String) {
        self.query = category
    }
}
