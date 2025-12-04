import Foundation
import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    
    // --- User Preferences (Persisted) ---
    
    @AppStorage("preferredLanguage") var preferredLanguage: String = "English"
    @AppStorage("preferredResolution") var preferredResolution: String = "4K UHD"
    
    // --- Configuration Options ---
    
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
        loadPlaylists()
    }
    
    private func loadPlaylists() {
        guard let repo = repository else { return }
        self.playlists = repo.getAllPlaylists()
    }
    
    // --- Actions ---
    
    func deletePlaylist(_ playlist: Playlist) {
        repository?.deletePlaylist(playlist)
        loadPlaylists()
    }
    
    func syncAll() async {
        // Trigger a global sync via the repository
        // This will now use the new logic to clean titles and populate metadata
        await repository?.syncAll()
    }
    
    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        print("✅ Image Cache Cleared")
    }
}
