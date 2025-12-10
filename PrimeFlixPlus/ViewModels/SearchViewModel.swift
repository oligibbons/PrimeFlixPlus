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
    
    // MARK: - History (Fixed)
    @Published var searchHistory: [String] = []
    
    // MARK: - UI State
    @Published var isLoading: Bool = false
    @Published var hasNoResults: Bool = false
    
    // MARK: - Dependencies
    private var repository: PrimeFlixRepository?
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Initialization
    // FIX: Accepts optional repository to ensure safe init
    init(repository: PrimeFlixRepository? = nil) {
        self.repository = repository
        // Load History from UserDefaults
        self.searchHistory = UserDefaults.standard.stringArray(forKey: "SearchHistory") ?? []
        setupSubscriptions()
    }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
    }
    
    // MARK: - History Management
    
    func addToHistory(_ term: String) {
        guard !term.isEmpty else { return }
        
        // Remove duplicates and move to top
        if let index = searchHistory.firstIndex(of: term) {
            searchHistory.remove(at: index)
        }
        searchHistory.insert(term, at: 0)
        
        // Cap at 10 items
        if searchHistory.count > 10 {
            searchHistory.removeLast()
        }
        
        saveHistory()
    }
    
    func clearHistory() {
        searchHistory.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        UserDefaults.standard.set(searchHistory, forKey: "SearchHistory")
    }
    
    // MARK: - Search Logic
    
    private func setupSubscriptions() {
        // 1. Debounced Search Trigger
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newQuery in
                self?.handleQueryChange(newQuery)
            }
            .store(in: &cancellables)
        
        // 2. Scope Change (Immediate)
        $selectedScope
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.handleQueryChange(self.query)
            }
            .store(in: &cancellables)
    }
    
    private func handleQueryChange(_ newQuery: String) {
        searchTask?.cancel()
        
        let cleanQuery = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanQuery.isEmpty {
            clearResults()
            return
        }
        
        performLocalSearch(query: cleanQuery)
    }
    
    private func performLocalSearch(query: String) {
        guard let repo = repository else { return }
        
        self.isLoading = true
        self.hasNoResults = false
        
        searchTask = Task {
            var filters = ChannelRepository.SearchFilters()
            switch selectedScope {
            case .movies: filters.onlyMovies = true
            case .series: filters.onlySeries = true
            case .live: filters.onlyLive = true
            case .all: break
            }
            
            // Execute Search via Repository
            let results = await repo.searchHybrid(query: query, filters: filters)
            
            if !Task.isCancelled {
                withAnimation(.easeInOut) {
                    self.movies = results.movies
                    self.series = results.series
                    self.liveChannels = results.live
                    
                    let totalCount = results.movies.count + results.series.count + results.live.count
                    self.hasNoResults = (totalCount == 0)
                    self.isLoading = false
                }
            }
        }
    }
    
    func clearResults() {
        self.movies = []
        self.series = []
        self.liveChannels = []
        self.hasNoResults = false
        self.isLoading = false
    }
}
