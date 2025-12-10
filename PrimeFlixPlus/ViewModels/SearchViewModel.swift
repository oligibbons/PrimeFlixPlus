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
    
    // MARK: - UI State
    @Published var isLoading: Bool = false
    @Published var hasNoResults: Bool = false
    
    // MARK: - Dependencies
    private var repository: PrimeFlixRepository?
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Initialization
    init() {
        setupSubscriptions()
    }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
    }
    
    private func setupSubscriptions() {
        // 1. Debounced Search Trigger
        // Wait 0.5s to avoid hammering the database while typing
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
                // Re-run search with new scope immediately
                self.handleQueryChange(self.query)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Logic
    
    private func handleQueryChange(_ newQuery: String) {
        // Cancel any pending search
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
            // 1. Configure Filters based on Scope
            var filters = ChannelRepository.SearchFilters()
            switch selectedScope {
            case .movies: filters.onlyMovies = true
            case .series: filters.onlySeries = true
            case .live: filters.onlyLive = true
            case .all: break
            }
            
            // 2. Execute Search on Background Thread via Repository
            // This calls the existing local hybrid search in ChannelRepository
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
