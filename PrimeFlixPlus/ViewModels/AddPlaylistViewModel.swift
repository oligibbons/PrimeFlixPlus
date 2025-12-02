import Foundation
import Combine
import SwiftUI

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
        
        withAnimation {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        var cleanUrl = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanUrl.hasSuffix("/") { cleanUrl.removeLast() }
        if !cleanUrl.lowercased().hasPrefix("http") {
            cleanUrl = "http://\(cleanUrl)"
        }
        
        let combinedUrl = "\(cleanUrl)|\(username)|\(password)"
        let title = URL(string: cleanUrl)?.host ?? "Xtream Playlist"
        
        guard let repo = repository else { return }
        
        // This will trigger the sync logic in Repository, which updates the global Overlay
        repo.addPlaylist(title: title, url: combinedUrl, source: .xtream)
        
        // Allow UI to update
        try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        
        withAnimation {
            self.isLoading = false
            self.isSuccess = true
        }
    }
}
