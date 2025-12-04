import Foundation
import SwiftUI
import Combine

// MARK: - Category Preferences Manager
// Shared logic for filtering and cleaning group names based on settings
class CategoryPreferences {
    static let shared = CategoryPreferences()
    
    private let hiddenKey = "userHiddenCategories"
    private var hiddenCategories: Set<String> {
        get {
            let list = UserDefaults.standard.array(forKey: hiddenKey) as? [String] ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: hiddenKey)
        }
    }
    
    // Define prefixes to KEEP for each language.
    // If a group starts with a country code NOT in this list, it is filtered out.
    private let languagePrefixes: [String: [String]] = [
        "English": ["EN", "US", "UK", "CA", "AU", "IE", "4K", "UHD", "VIP"],
        "Dutch": ["NL", "BE", "EU"],
        "French": ["FR", "BE", "CH", "CA"],
        "German": ["DE", "AT", "CH"],
        "Spanish": ["ES", "MX", "LATAM"],
        "Italian": ["IT"],
        "Arabic": ["AR", "AE", "SA", "QA"],
        "Turkish": ["TR"],
        "Portuguese": ["PT", "BR"],
        "Russian": ["RU"],
        "Polish": ["PL"],
        "Hindi": ["IN", "HI"]
    ]
    
    func isCategoryHidden(_ group: String) -> Bool {
        return hiddenCategories.contains(group)
    }
    
    func toggleCategory(_ group: String) {
        var current = hiddenCategories
        if current.contains(group) {
            current.remove(group)
        } else {
            current.insert(group)
        }
        hiddenCategories = current
    }
    
    // MARK: - Core Logic
    
    func shouldShow(group: String, language: String) -> Bool {
        // 1. Manual Hide check
        if isCategoryHidden(group) { return false }
        
        // 2. Language Filter
        // If the group has a prefix like "NL |", check if "NL" is allowed for the current language.
        if let prefix = extractPrefix(from: group) {
            let allowed = languagePrefixes[language] ?? []
            // If the prefix is a known country code (2-3 letters), but NOT in our allowed list, hide it.
            // We verify it's a country code by length to avoid hiding "Action" or "Sci-Fi".
            if prefix.count <= 3 && !allowed.contains(prefix) {
                // Special case: "4K", "3D", "VIP" are usually universal, keep them if unsure
                if ["4K", "3D", "VIP", "UHD"].contains(prefix) { return true }
                return false
            }
        }
        
        return true
    }
    
    func cleanName(_ group: String) -> String {
        // Regex to find "XX | " or "XX : " pattern
        // We strip it ONLY if it matches the standard IPTV format
        if let range = group.range(of: "^[A-Z]{2,3}\\s*[|:-]\\s*", options: .regularExpression) {
            let clean = String(group[range.upperBound...])
            return clean.isEmpty ? group : clean
        }
        return group
    }
    
    private func extractPrefix(from group: String) -> String? {
        // Grab the first part before "|" or ":"
        let parts = group.components(separatedBy: CharacterSet(charactersIn: "|:-"))
        if let first = parts.first {
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            // Check if it looks like a country code (2-3 uppercase letters)
            if trimmed.count >= 2 && trimmed.count <= 3 && trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) {
                return trimmed
            }
        }
        return nil
    }
}

@MainActor
class SettingsViewModel: ObservableObject {
    
    // --- User Preferences ---
    @AppStorage("preferredLanguage") var preferredLanguage: String = "English"
    @AppStorage("preferredResolution") var preferredResolution: String = "4K UHD"
    
    // --- Configuration Options ---
    let availableLanguages = [
        "English", "Dutch", "French", "German", "Spanish",
        "Italian", "Russian", "Turkish", "Portuguese", "Polish", "Hindi"
    ]
    
    let availableResolutions = ["4K UHD", "1080p", "720p", "SD"]
    
    // --- State ---
    @Published var playlists: [Playlist] = []
    
    // For the "Manage Categories" UI
    @Published var allCategories: [String] = []
    
    private var repository: PrimeFlixRepository?
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        loadPlaylists()
        loadCategories()
    }
    
    private func loadPlaylists() {
        guard let repo = repository else { return }
        self.playlists = repo.getAllPlaylists()
    }
    
    private func loadCategories() {
        // Fetch all unique groups from Core Data to list them in Settings
        guard let repo = repository else { return }
        
        // We fetch generic groups for all types to get a complete list
        let movieGroups = repo.getGroups(playlistUrl: playlists.first?.url ?? "", type: .movie)
        let seriesGroups = repo.getGroups(playlistUrl: playlists.first?.url ?? "", type: .series)
        let liveGroups = repo.getGroups(playlistUrl: playlists.first?.url ?? "", type: .live)
        
        // Merge and Sort by CLEANED name (so "EN | Action" appears under A, not E)
        let combined = Set(movieGroups + seriesGroups + liveGroups)
        
        self.allCategories = combined.sorted {
            let clean1 = CategoryPreferences.shared.cleanName($0)
            let clean2 = CategoryPreferences.shared.cleanName($1)
            return clean1.localizedStandardCompare(clean2) == .orderedAscending
        }
    }
    
    // --- Actions ---
    
    func deletePlaylist(_ playlist: Playlist) {
        repository?.deletePlaylist(playlist)
        loadPlaylists()
    }
    
    func toggleCategoryVisibility(_ group: String) {
        CategoryPreferences.shared.toggleCategory(group)
        objectWillChange.send() // Trigger UI update
    }
    
    func isHidden(_ group: String) -> Bool {
        return CategoryPreferences.shared.isCategoryHidden(group)
    }
    
    func cleanName(_ group: String) -> String {
        return CategoryPreferences.shared.cleanName(group)
    }
    
    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
    }
}
