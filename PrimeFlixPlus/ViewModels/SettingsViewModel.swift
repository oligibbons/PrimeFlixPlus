import Foundation
import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    
    // --- Preferences ---
    // Persist to UserDefaults automatically so they survive app restarts
    @AppStorage("preferredLanguage") var preferredLanguage: String = "English"
    @AppStorage("preferredResolution") var preferredResolution: String = "4K UHD"
    
    // Available Options for the Picker
    let availableLanguages = [
        "English", "Arabic", "French", "Spanish", "German",
        "Italian", "Russian", "Turkish", "Portuguese", "Multi-Audio"
    ]
    
    let availableResolutions = ["4K UHD", "1080p", "720p", "SD"]
    
    // --- Playlist Management ---
    @Published var playlists: [Playlist] = []
    private var repository: PrimeFlixRepository?
    
    init() {}
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        loadPlaylists()
    }
    
    func loadPlaylists() {
        guard let repo = repository else { return }
        self.playlists = repo.getAllPlaylists()
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        repository?.deletePlaylist(playlist)
        loadPlaylists()
    }
    
    func syncAll() async {
        await repository?.syncAll()
    }
    
    func clearCache() {
        // Clear URLCache (covers AsyncImage)
        URLCache.shared.removeAllCachedResponses()
    }
}
