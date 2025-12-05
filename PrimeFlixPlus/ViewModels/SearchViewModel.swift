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
    
    // MARK: - Dependencies
    private var repository: PrimeFlixRepository?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    // Added custom init to allow SearchView to inject the starting scope
    init(initialScope: SearchScope = .library) {
        self.selectedScope = initialScope
    }
    
    // MARK: - Configuration
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // 1. Watch Query (Debounced)
        // We delay the search slightly while typing to avoid hammering the database
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
        // If user switches tabs (Library <-> Live TV), search immediately
        $selectedScope
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.performSearch()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Search Logic
    
    func performSearch() {
        guard let repo = repository, !query.isEmpty else {
            clearResults()
            return
        }
        
        self.isLoading = true
        self.hasNoResults = false
        
        let currentQuery = query
        let currentScope = selectedScope
        
        // Use a detached task to utilize the repository's background context logic safely
        Task {
            // Create a new background context for this specific search operation
            // to avoid blocking the main thread or the view context
            let bgContext = repo.container.newBackgroundContext()
            
            await bgContext.perform { [weak self] in
                guard let self = self else { return }
                
                let searchRepo = ChannelRepository(context: bgContext)
                
                if currentScope == .library {
                    // --- LIBRARY SEARCH ---
                    // Searches Movies, Series, and EPG
                    let results = searchRepo.search(query: currentQuery)
                    
                    // Extract Object IDs to pass back to MainActor safely
                    // We cannot pass NSManagedObjects between contexts/threads
                    let movieIDs = results.movies.map { $0.objectID }
                    let seriesIDs = results.series.map { $0.objectID }
                    
                    Task { @MainActor in
                        // Re-fetch objects on the main context for the UI
                        let viewContext = repo.container.viewContext
                        self.movies = movieIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                        self.series = seriesIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                        
                        self.isLoading = false
                        self.hasNoResults = self.movies.isEmpty && self.series.isEmpty
                    }
                    
                } else {
                    // --- LIVE TV SEARCH ---
                    // Searches Categories (Groups) and Channels specifically for Live TV
                    let (categories, channels) = searchRepo.searchLiveContent(query: currentQuery)
                    
                    // Extract Object IDs for channels
                    // Categories are just Strings, so they are safe to pass directly
                    let channelIDs = channels.map { $0.objectID }
                    
                    Task { @MainActor in
                        let viewContext = repo.container.viewContext
                        self.liveCategories = categories
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
