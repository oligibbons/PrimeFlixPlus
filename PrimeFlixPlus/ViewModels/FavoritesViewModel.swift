import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class FavoritesViewModel: ObservableObject {
    
    @Published var movies: [Channel] = []
    @Published var series: [Channel] = []
    @Published var liveChannels: [Channel] = []
    
    @Published var isLoading: Bool = true
    
    private var repository: PrimeFlixRepository?
    private var cancellables = Set<AnyCancellable>()
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        
        refreshData()
        
        // Live Update: Listen for changes (e.g., toggleFavorite called in DetailsView)
        repository.objectWillChange
            .sink { [weak self] _ in
                Task {
                    // Small delay to allow Core Data commit to propagate
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    await self?.refreshData()
                }
            }
            .store(in: &cancellables)
    }
    
    func refreshData() {
        guard let repo = repository else { return }
        
        Task.detached(priority: .userInitiated) {
            let favMovies = repo.getFavorites(type: "movie")
            let favSeries = repo.getFavorites(type: "series")
            let favLive = repo.getFavorites(type: "live")
            
            await MainActor.run {
                withAnimation(.easeInOut) {
                    self.movies = favMovies
                    self.series = favSeries
                    self.liveChannels = favLive
                    self.isLoading = false
                }
            }
        }
    }
}
