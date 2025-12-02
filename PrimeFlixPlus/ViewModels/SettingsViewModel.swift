import Foundation
import CoreData
import Combine

@MainActor // FIXED: Entire class runs on Main Actor
class SettingsViewModel: ObservableObject {
    
    @Published var playlists: [Playlist] = []
    @Published var isLoading: Bool = false
    @Published var message: String? = nil
    
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
        self.message = "Syncing \(playlist.title)..."
        self.isLoading = true
        
        await repo.syncPlaylist(playlistTitle: playlist.title, playlistUrl: playlist.url, source: DataSourceType(rawValue: playlist.source) ?? .m3u)
        
        self.isLoading = false
        self.message = "Sync Complete!"
        try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
        self.message = nil
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        guard let context = playlist.managedObjectContext else { return }
        context.delete(playlist)
        try? context.save()
        loadPlaylists()
    }
}
