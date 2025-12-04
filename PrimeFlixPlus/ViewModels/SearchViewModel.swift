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
    
    struct LiveSearchResult: Identifiable {
        let id = UUID()
        let channel: Channel
        let currentProgram: Programme?
    }
    
    init() {
        $searchText
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main) // Typing comfort
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
        
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.movieResults = []
            self.seriesResults = []
            self.liveResults = []
            self.isEmpty = true
            self.isSearching = false
            return
        }
        
        self.isSearching = true
        self.isEmpty = false
        
        // CRITICAL: Run search in a DETACHED task to keep keyboard responsive.
        // We use a background context to perform the fetch, then pass ObjectIDs back to Main.
        Task.detached(priority: .userInitiated) {
            let context = repo.container.newBackgroundContext()
            
            // 1. Perform Fetch on Background Context
            // We use a helper struct to transport IDs safely across threads
            struct BackgroundResults {
                let movieIDs: [NSManagedObjectID]
                let seriesIDs: [NSManagedObjectID]
                let liveIDs: [NSManagedObjectID]
                let programIDs: [NSManagedObjectID]
            }
            
            var safeResults: BackgroundResults?
            
            context.performAndWait {
                let searchRepo = ChannelRepository(context: context)
                let rawResults = searchRepo.search(query: query)
                
                safeResults = BackgroundResults(
                    movieIDs: rawResults.movies.map { $0.objectID },
                    seriesIDs: rawResults.series.map { $0.objectID },
                    liveIDs: rawResults.liveChannels.map { $0.objectID },
                    programIDs: rawResults.livePrograms.map { $0.objectID }
                )
            }
            
            guard let results = safeResults else { return }
            
            // 2. Resolve on Main Actor
            await MainActor.run {
                // Ensure we are still searching for the same thing (basic cancellation check)
                // In a production app, we might use a cancellation token, but this is sufficient for now.
                
                let viewContext = repo.container.viewContext
                
                // Re-fetch objects using IDs (very fast)
                let finalMovies = results.movieIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                let finalSeries = results.seriesIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                let finalLive = results.liveIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                let finalProgs = results.programIDs.compactMap { try? viewContext.existingObject(with: $0) as? Programme }
                
                // Process Live Results (Map Programs to Channels)
                var processedLive: [LiveSearchResult] = []
                
                // Add direct Channel matches
                for ch in finalLive {
                    processedLive.append(LiveSearchResult(channel: ch, currentProgram: nil))
                }
                
                // Add Program matches
                // We need to look up the channel for the program.
                // Since we are on Main Actor, we can use the repository helper logic or direct fetch.
                for prog in finalProgs {
                    // Optimized: Find channel in existing list or fetch if needed
                    let req = NSFetchRequest<Channel>(entityName: "Channel")
                    // Heuristic: URL contains the channel ID embedded in the program
                    req.predicate = NSPredicate(format: "url CONTAINS[cd] '/' + %@ + '.'", prog.channelId)
                    req.fetchLimit = 1
                    
                    if let ch = (try? viewContext.fetch(req))?.first {
                        // Dedup: Don't add if the channel itself was already matched by title
                        if !processedLive.contains(where: { $0.channel.url == ch.url }) {
                            processedLive.append(LiveSearchResult(channel: ch, currentProgram: prog))
                        }
                    }
                }
                
                self.movieResults = finalMovies
                self.seriesResults = finalSeries
                self.liveResults = processedLive
                self.isSearching = false
                self.isEmpty = finalMovies.isEmpty && finalSeries.isEmpty && processedLive.isEmpty
            }
        }
    }
}
