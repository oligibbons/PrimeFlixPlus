import Foundation
import Combine

@MainActor
class AddPlaylistViewModel: ObservableObject {
    
    @Published var serverUrl: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isSuccess: Bool = false
    
    private var repository: PrimeFlixRepository?
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
    }
    
    func addAccount() async {
        guard !serverUrl.isEmpty, !username.isEmpty, !password.isEmpty else {
            self.errorMessage = "All fields are required"
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        // 1. Clean URL
        var cleanUrl = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanUrl.hasSuffix("/") { cleanUrl.removeLast() }
        if !cleanUrl.lowercased().hasPrefix("http") {
            cleanUrl = "http://\(cleanUrl)"
        }
        
        // 2. Pack Credentials (Internal Format)
        // Format: server|username|password
        let combinedUrl = "\(cleanUrl)|\(username)|\(password)"
        
        // 3. Determine Title (Host)
        let title = URL(string: cleanUrl)?.host ?? "Xtream Playlist"
        
        // 4. Call Repository
        guard let repo = repository else { return }
        
        // We use the repo's sync logic to verify if it works
        // Note: In a real app, you might want a simple "check auth" call first.
        // Here we blindly add and sync.
        repo.addPlaylist(title: title, url: combinedUrl, source: .xtream)
        
        // Simulate success delay/check
        // In the repo, addPlaylist triggers a background sync task.
        // We assume success for the UI flow to proceed.
        try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        
        self.isLoading = false
        self.isSuccess = true
    }
}
