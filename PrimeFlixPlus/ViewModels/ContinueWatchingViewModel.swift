import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class ContinueWatchingViewModel: ObservableObject {
    
    @Published var movies: [Channel] = []
    @Published var series: [Channel] = []
    @Published var liveChannels: [Channel] = []
    
    @Published var isLoading: Bool = true
    
    private var repository: PrimeFlixRepository?
    private var cancellables = Set<AnyCancellable>()
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        
        // Initial Fetch
        refreshData()
        
        // Live Update: Listen for changes in the repository (e.g., saveProgress called)
        repository.objectWillChange
            .sink { [weak self] _ in
                // Debounce slightly to avoid rapid re-fetches during scrubbing
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await self?.refreshData()
                }
            }
            .store(in: &cancellables)
    }
    
    func refreshData() {
        guard let repo = repository else { return }
        
        Task.detached(priority: .userInitiated) {
            // Use existing repository logic which handles sophisticated percentage/next-episode checks
            let rawMovies = repo.getSmartContinueWatching(type: "movie")
            let rawSeries = repo.getSmartContinueWatching(type: "series")
            let rawLive = repo.getSmartContinueWatching(type: "live")
            
            // Apply specific limits
            let limitedMovies = Array(rawMovies.prefix(20))
            let limitedSeries = Array(rawSeries.prefix(20))
            let limitedLive = Array(rawLive.prefix(10)) // Requirement: Last 10 for Live TV
            
            await MainActor.run {
                withAnimation(.easeInOut) {
                    self.movies = limitedMovies
                    self.series = limitedSeries
                    self.liveChannels = limitedLive
                    self.isLoading = false
                }
            }
        }
    }
}
