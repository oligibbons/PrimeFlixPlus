import Foundation
import SwiftUI
import Combine

// MARK: - Category Preferences Manager
// Shared logic for filtering and cleaning group names based on settings
class CategoryPreferences {
    static let shared = CategoryPreferences()
    
    // NOTIFICATION: Broadcasts when categories change so HomeView can refresh
    static let didChangeNotification = Notification.Name("CategoryPreferencesDidChange")
    
    private let hiddenKey = "userHiddenCategories"
    private var hiddenCategories: Set<String> {
        get {
            let list = UserDefaults.standard.array(forKey: hiddenKey) as? [String] ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: hiddenKey)
            // Notify observers (HomeViewModel)
            NotificationCenter.default.post(name: CategoryPreferences.didChangeNotification, object: nil)
        }
    }
    
    // Define prefixes to KEEP for each language.
    // If a group starts with a country code NOT in this list, it is filtered out by isForeign().
    private let languagePrefixes: [String: [String]] = [
        "English": ["EN", "US", "UK", "CA", "AU", "IE", "4K", "UHD", "VIP", "DOC"],
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
    
    /// Mass hides a list of categories (Used for Auto-Hide feature)
    func bulkHide(_ groups: [String]) {
        var current = hiddenCategories
        var changed = false
        for group in groups {
            if !current.contains(group) {
                current.insert(group)
                changed = true
            }
        }
        if changed {
            hiddenCategories = current
        }
    }
    
    // MARK: - Core Logic
    
    func shouldShow(group: String, language: String) -> Bool {
        // 1. Manual Hide check
        if isCategoryHidden(group) { return false }
        return true
    }
    
    /// Determines if a category is considered "Foreign" based on the user's language.
    func isForeign(group: String, language: String) -> Bool {
        guard let prefix = extractPrefix(from: group) else { return false }
        
        let allowed = languagePrefixes[language] ?? []
        
        // If the prefix is a known country code (2-3 letters), but NOT in our allowed list, it's foreign.
        if prefix.count >= 2 && prefix.count <= 3 {
            // Safety check: Don't hide technical tags
            if ["4K", "3D", "VIP", "UHD", "HDR", "VOD", "FHD", "HEVC"].contains(prefix) {
                return false
            }
            
            if !allowed.contains(prefix) {
                return true
            }
        }
        
        return false
    }
    
    func cleanName(_ group: String) -> String {
        // Regex to find "XX | " or "XX : " pattern
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
            // Check if it looks like a country code
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
    @AppStorage("autoHideForeign") var autoHideForeign: Bool = false
    
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
    
    // MARK: - Auto-Hide Logic
    
    /// Scans all known categories and hides those that do not match the preferred language.
    func runAutoHidingLogic() {
        guard autoHideForeign else { return }
        
        // Ensure we have data to process
        if allCategories.isEmpty {
            loadCategories()
        }
        
        let language = preferredLanguage
        
        // Identify "Foreign" categories
        let foreignCategories = allCategories.filter { group in
            CategoryPreferences.shared.isForeign(group: group, language: language)
        }
        
        guard !foreignCategories.isEmpty else {
            print("⚠️ No foreign categories found to hide.")
            return
        }
        
        print("🌍 Auto-Hiding \(foreignCategories.count) foreign categories for language: \(language)")
        
        // Bulk hide them (Adding to the blacklist)
        // This triggers the Notification due to the setter in CategoryPreferences
        CategoryPreferences.shared.bulkHide(foreignCategories)
        
        // Refresh UI
        objectWillChange.send()
    }
}
