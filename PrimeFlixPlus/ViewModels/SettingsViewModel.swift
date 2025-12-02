import Foundation
import CoreData
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    
    @Published var playlists: [Playlist] = []
    private var repository: PrimeFlixRepository?
    
    init() {}
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        loadPlaylists()
    }
    
    private func loadPlaylists() {
        guard let repo = repository else { return }
        self.playlists = repo.getAllPlaylists()
    }
    
    func syncPlaylist(_ playlist: Playlist) async {
        guard let repo = repository else { return }
        guard let source = DataSourceType(rawValue: playlist.source) else { return }
        
        // Triggers the repo's global sync logic which updates the overlay
        await repo.syncPlaylist(playlistTitle: playlist.title, playlistUrl: playlist.url, source: source)
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        repository?.deletePlaylist(playlist)
        // Refresh local list
        loadPlaylists()
    }
}
