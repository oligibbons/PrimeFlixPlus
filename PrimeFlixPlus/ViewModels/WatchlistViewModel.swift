import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class WatchlistViewModel: ObservableObject {
    
    @Published var movies: [Channel] = []
    @Published var series: [Channel] = []
    @Published var liveChannels: [Channel] = []
    
    @Published var isLoading: Bool = true
    
    private var repository: PrimeFlixRepository?
    private var cancellables = Set<AnyCancellable>()
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        
        // Prevent duplicate subscriptions if view re-appears
        cancellables.removeAll()
        
        // Initial Fetch
        refreshData()
        
        // Live Update: Listen for changes in the repository (e.g. toggleWatchlist)
        repository.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main) // Debounce to prevent rapid UI flashes
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
    }
    
    func refreshData() {
        guard let repo = repository else { return }
        
        Task {
            // Fetch items where inWatchlist == true
            // Note: repo.getWatchlist now correctly handles episodes/series logic
            let wMovies = repo.getWatchlist(type: "movie")
            let wSeries = repo.getWatchlist(type: "series")
            let wLive = repo.getWatchlist(type: "live")
            
            withAnimation(.easeInOut) {
                self.movies = wMovies
                self.series = wSeries
                self.liveChannels = wLive
                self.isLoading = false
            }
        }
    }
}
