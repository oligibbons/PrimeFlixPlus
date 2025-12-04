import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class SearchViewModel: ObservableObject {
    
    @Published var searchText: String = ""
    
    // Results
    @Published var movieResults: [Channel] = []
    @Published var seriesResults: [Channel] = []
    @Published var liveResults: [LiveSearchResult] = []
    
    // State
    @Published var isSearching: Bool = false
    @Published var isEmpty: Bool = true
    
    private var repository: PrimeFlixRepository?
    private var cancellables = Set<AnyCancellable>()
    
    // Keep track of the running task so we can cancel it
    private var searchTask: Task<Void, Never>?
    
    struct LiveSearchResult: Identifiable {
        let id = UUID()
        let channel: Channel
        let currentProgram: Programme?
    }
    
    init() {
        $searchText
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main) // Debounce typing
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query)
            }
            .store(in: &cancellables)
    }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
    }
    
    private func performSearch(_ query: String) {
        guard let repo = repository else { return }
        
        // 1. Cancel any existing search to save resources
        searchTask?.cancel()
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedQuery.isEmpty {
            self.movieResults = []
            self.seriesResults = []
            self.liveResults = []
            self.isEmpty = true
            self.isSearching = false
            return
        }
        
        self.isSearching = true
        self.isEmpty = false
        
        // 2. Start new search task
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            
            // Create a background context for thread safety
            let context = repo.container.newBackgroundContext()
            
            // Perform Fetch on Background Context
            struct BackgroundResults {
                let movieIDs: [NSManagedObjectID]
                let seriesIDs: [NSManagedObjectID]
                let liveIDs: [NSManagedObjectID]
                let programIDs: [NSManagedObjectID]
            }
            
            var safeResults: BackgroundResults?
            
            await context.perform {
                // Check cancellation before doing work
                if Task.isCancelled { return }
                
                let searchRepo = ChannelRepository(context: context)
                let rawResults = searchRepo.search(query: trimmedQuery)
                
                if Task.isCancelled { return }
                
                safeResults = BackgroundResults(
                    movieIDs: rawResults.movies.map { $0.objectID },
                    seriesIDs: rawResults.series.map { $0.objectID },
                    liveIDs: rawResults.liveChannels.map { $0.objectID },
                    programIDs: rawResults.livePrograms.map { $0.objectID }
                )
            }
            
            guard let results = safeResults, !Task.isCancelled else { return }
            
            // 3. Update UI on Main Actor
            // FIX: Explicitly capture [weak self] here to satisfy compiler safety checks for concurrent code
            await MainActor.run { [weak self] in
                guard let strongSelf = self else { return }
                
                let viewContext = repo.container.viewContext
                
                // Re-fetch objects using IDs (very fast)
                let finalMovies = results.movieIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                let finalSeries = results.seriesIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                let finalLive = results.liveIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                let finalProgs = results.programIDs.compactMap { try? viewContext.existingObject(with: $0) as? Programme }
                
                // Process Live Results
                var processedLive: [LiveSearchResult] = []
                
                // Add direct Channel matches
                for ch in finalLive {
                    processedLive.append(LiveSearchResult(channel: ch, currentProgram: nil))
                }
                
                // Add Program matches (Live TV EPG)
                for prog in finalProgs {
                    // Optimization: Reuse existing fetch logic or simple lookup
                    // We assume URL contains ID for mapping
                    let req = NSFetchRequest<Channel>(entityName: "Channel")
                    req.predicate = NSPredicate(format: "url CONTAINS[cd] '/' + %@ + '.'", prog.channelId)
                    req.fetchLimit = 1
                    
                    if let ch = (try? viewContext.fetch(req))?.first {
                        // Dedup: Don't add if the channel is already in the list
                        if !processedLive.contains(where: { $0.channel.url == ch.url }) {
                            processedLive.append(LiveSearchResult(channel: ch, currentProgram: prog))
                        }
                    }
                }
                
                strongSelf.movieResults = finalMovies
                strongSelf.seriesResults = finalSeries
                strongSelf.liveResults = processedLive
                strongSelf.isSearching = false
                strongSelf.isEmpty = finalMovies.isEmpty && finalSeries.isEmpty && processedLive.isEmpty
            }
        }
    }
}
