import Foundation
import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    
    // --- User Preferences (Persisted) ---
    
    // These properties are saved to UserDefaults.
    // The UI binds directly to these, and DetailsViewModel reads them
    // to decide which file version to play automatically.
    
    @AppStorage("preferredLanguage") var preferredLanguage: String = "English"
    @AppStorage("preferredResolution") var preferredResolution: String = "4K UHD"
    
    // --- Configuration Options ---
    
    // Lists used by the Settings View Pickers
    let availableLanguages = [
        "English",
        "Arabic",
        "French",
        "Spanish",
        "German",
        "Italian",
        "Russian",
        "Turkish",
        "Portuguese",
        "Dutch",
        "Polish",
        "Hindi",
        "Multi-Audio"
    ]
    
    let availableResolutions = [
        "4K UHD",
        "1080p",
        "720p",
        "SD"
    ]
    
    // --- Playlist Management State ---
    
    @Published var playlists: [Playlist] = []
    
    private var repository: PrimeFlixRepository?
    
    init() {
        // No heavy work in init, wait for configure()
    }
    
    // --- Lifecycle ---
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        // Initial load of playlists for the management list
        loadPlaylists()
    }
    
    private func loadPlaylists() {
        guard let repo = repository else { return }
        self.playlists = repo.getAllPlaylists()
    }
    
    // --- Actions ---
    
    func deletePlaylist(_ playlist: Playlist) {
        // Forward the deletion request to the repository
        repository?.deletePlaylist(playlist)
        // Refresh our local list to update the UI immediately
        loadPlaylists()
    }
    
    func syncAll() async {
        // Trigger a global sync via the repository
        await repository?.syncAll()
    }
    
    func clearCache() {
        // Clears the URLCache used by AsyncImage
        // This frees up disk space and forces fresh image downloads next time
        URLCache.shared.removeAllCachedResponses()
        print("✅ Image Cache Cleared")
    }
}
