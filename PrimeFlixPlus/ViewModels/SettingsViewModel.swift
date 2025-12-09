import Foundation
import SwiftUI
import Combine

// MARK: - Category Preferences Manager
class CategoryPreferences {
    static let shared = CategoryPreferences()
    
    static let didChangeNotification = Notification.Name("CategoryPreferencesDidChange")
    
    private let hiddenKey = "userHiddenCategories"
    private var hiddenCategories: Set<String> {
        get {
            let list = UserDefaults.standard.array(forKey: hiddenKey) as? [String] ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: hiddenKey)
            NotificationCenter.default.post(name: CategoryPreferences.didChangeNotification, object: nil)
        }
    }
    
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
    
    func shouldShow(group: String, language: String) -> Bool {
        if isCategoryHidden(group) { return false }
        return true
    }
    
    func isForeign(group: String, language: String) -> Bool {
        guard let prefix = extractPrefix(from: group) else { return false }
        let allowed = languagePrefixes[language] ?? []
        
        if prefix.count >= 2 && prefix.count <= 3 {
            if ["4K", "3D", "VIP", "UHD", "HDR", "VOD", "FHD", "HEVC"].contains(prefix) { return false }
            if !allowed.contains(prefix) { return true }
        }
        return false
    }
    
    func cleanName(_ group: String) -> String {
        if let range = group.range(of: "^[A-Z]{2,3}\\s*[|:-]\\s*", options: .regularExpression) {
            let clean = String(group[range.upperBound...])
            return clean.isEmpty ? group : clean
        }
        return group
    }
    
    private func extractPrefix(from group: String) -> String? {
        let parts = group.components(separatedBy: CharacterSet(charactersIn: "|:-"))
        if let first = parts.first {
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
    @AppStorage("defaultPlaybackSpeed") var defaultPlaybackSpeed: Double = 1.0
    
    // --- Playback Optimization Settings ---
    
    // NEW: Capacity Limit (MB). Default 300MB.
    // 300MB = ~40s of 4K, or ~3m of 1080p.
    @AppStorage("bufferMemoryLimit") var bufferMemoryLimit: Int = 300
    
    @AppStorage("useHardwareDecoding") var useHardwareDecoding: Bool = true
    @AppStorage("maxStreamResolution") var maxStreamResolution: String = "Unlimited"
    @AppStorage("defaultDeinterlace") var defaultDeinterlace: Bool = false
    @AppStorage("defaultAspectRatio") var defaultAspectRatio: String = "Default"
    
    // --- Configuration Options ---
    let availableLanguages = [
        "English", "Dutch", "French", "German", "Spanish",
        "Italian", "Russian", "Turkish", "Portuguese", "Polish", "Hindi"
    ]
    
    let availableResolutions = ["4K UHD", "1080p", "720p", "SD"]
    
    // Optimization Presets (RAM Allocations)
    let bufferOptions: [(String, Int)] = [
        ("Light (100 MB)", 100),
        ("Standard (200 MB)", 200),
        ("High (300 MB)", 300),
        ("Ultra (500 MB)", 500)
    ]
    
    let resolutionCaps = ["Unlimited", "1080p", "720p"]
    
    // --- State ---
    @Published var playlists: [Playlist] = []
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
        guard let repo = repository else { return }
        
        let movieGroups = repo.getGroups(playlistUrl: playlists.first?.url ?? "", type: .movie)
        let seriesGroups = repo.getGroups(playlistUrl: playlists.first?.url ?? "", type: .series)
        let liveGroups = repo.getGroups(playlistUrl: playlists.first?.url ?? "", type: .live)
        
        let combined = Set(movieGroups + seriesGroups + liveGroups)
        
        self.allCategories = combined.sorted { (a: String, b: String) -> Bool in
            let clean1 = CategoryPreferences.shared.cleanName(a)
            let clean2 = CategoryPreferences.shared.cleanName(b)
            return clean1.localizedStandardCompare(clean2) == .orderedAscending
        }
    }
    
    // --- Actions ---
    
    func applyStreamOptimize() {
        // "Stream Optimize" - Maximum Performance Preset
        // 400MB is safe for ATV 4K (has 3GB+ RAM), allows huge buffer for 1080p
        self.bufferMemoryLimit = 400
        self.useHardwareDecoding = true
        self.maxStreamResolution = "1080p" // Prioritize smoothness over pixel count
        self.defaultDeinterlace = true
        
        objectWillChange.send()
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        repository?.deletePlaylist(playlist)
        loadPlaylists()
    }
    
    func toggleCategoryVisibility(_ group: String) {
        CategoryPreferences.shared.toggleCategory(group)
        objectWillChange.send()
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
    
    func forceUpdate() {
        Task { await repository?.syncAll(force: true) }
    }
    
    func nuclearResync() {
        guard let repo = repository else { return }
        Task {
            for playlist in playlists {
                await repo.nuclearResync(playlist: playlist)
            }
        }
    }
    
    func runAutoHidingLogic() {
        guard autoHideForeign else { return }
        if allCategories.isEmpty { loadCategories() }
        
        let language = preferredLanguage
        let foreignCategories = allCategories.filter { group in
            CategoryPreferences.shared.isForeign(group: group, language: language)
        }
        
        guard !foreignCategories.isEmpty else { return }
        CategoryPreferences.shared.bulkHide(foreignCategories)
        objectWillChange.send()
    }
}
