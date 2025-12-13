import Foundation
import SwiftUI
import Combine
import CoreData

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
    
    // --- Player Customization ---
    // UPDATED: Default sensitivity reduced to 0.05 (5%)
    @AppStorage("scrubSensitivity") var scrubSensitivity: Double = 0.05
    @AppStorage("subtitleScale") var subtitleScale: Double = 1.0        // 1.0 = Normal
    @AppStorage("areSubtitlesEnabled") var areSubtitlesEnabled: Bool = true
    @AppStorage("vpnAlertEnabled") var vpnAlertEnabled: Bool = true
    
    // --- Playback Optimization Settings ---
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
    
    // Sensitivity Presets (Updated Scale)
    let sensitivityOptions: [(String, Double)] = [
        ("Fine (2%)", 0.02),
        ("Standard (5%)", 0.05),
        ("Fast (10%)", 0.10),
        ("Very Fast (20%)", 0.20)
    ]
    
    // Subtitle Sizes
    let subtitleSizes: [(String, Double)] = [
        ("Small", 0.75),
        ("Standard", 1.0),
        ("Large", 1.25),
        ("Extra Large", 1.5)
    ]
    
    // Optimization Presets (RAM Allocations)
    let bufferOptions: [(String, Int)] = [
        ("Light (100 MB)", 100),
        ("Standard (300 MB)", 300),
        ("Heavy (500 MB)", 500)
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
        // "Stream Optimize" - Safe Defaults for Stability
        self.bufferMemoryLimit = 300
        self.useHardwareDecoding = true
        self.maxStreamResolution = "1080p"
        self.defaultDeinterlace = true
        self.scrubSensitivity = 0.05
        
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
        
        // 1. Deep Clean: Delete all Data Entities
        let context = repo.container.newBackgroundContext()
        context.performAndWait {
            let entities = ["Channel", "Programme", "MediaMetadata", "WatchProgress"]
            for entity in entities {
                let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
                let delete = NSBatchDeleteRequest(fetchRequest: fetch)
                _ = try? context.execute(delete)
            }
            try? context.save()
        }
        
        // 2. Clear User Settings (Optional, but "Nuclear" implies total reset)
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        
        // 3. Restore Default Preferences (since we wiped UserDefaults)
        self.scrubSensitivity = 0.05
        self.bufferMemoryLimit = 300
        
        // 4. Trigger Fresh Sync
        Task {
            await MainActor.run {
                // Refresh UI state immediately
                self.playlists = []
                self.allCategories = []
            }
            await repo.syncAll(force: true)
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
