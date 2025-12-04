import Foundation
import Combine
import SwiftUI

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
    
    // Wrapper to combine Channel + EPG info
    struct LiveSearchResult: Identifiable {
        let id = UUID()
        let channel: Channel
        let currentProgram: Programme? // If search matched the Program
    }
    
    init() {
        $searchText
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
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
            return
        }
        
        self.isSearching = true
        self.isEmpty = false
        
        // Run search in background context logic (via repository helper)
        Task {
            // We need to access the underlying ChannelRepository from PrimeFlixRepository
            // Since PrimeFlixRepository hides it, we should add a passthrough or use the container directly.
            // For now, let's assume we can access a search method on PrimeFlixRepository
            // OR create a temporary ChannelRepository here using the context.
            
            let context = repo.container.viewContext
            let searchRepo = ChannelRepository(context: context)
            
            let results = searchRepo.search(query: query)
            
            // Post-process Live TV results to merge Channels and Programs
            var processedLive: [LiveSearchResult] = []
            
            // 1. Add direct Channel matches
            for ch in results.liveChannels {
                processedLive.append(LiveSearchResult(channel: ch, currentProgram: nil))
            }
            
            // 2. Add Program matches (map back to Channel)
            for prog in results.livePrograms {
                if let ch = searchRepo.getChannel(byId: prog.channelId) {
                    // Avoid duplicates if we already added this channel via title match
                    if !processedLive.contains(where: { $0.channel.url == ch.url }) {
                        processedLive.append(LiveSearchResult(channel: ch, currentProgram: prog))
                    }
                }
            }
            
            await MainActor.run {
                self.movieResults = results.movies
                self.seriesResults = results.series
                self.liveResults = processedLive
                self.isSearching = false
            }
        }
    }
}
