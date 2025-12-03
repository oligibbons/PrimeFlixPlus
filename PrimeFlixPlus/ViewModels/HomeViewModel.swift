import Foundation
import CoreData
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    
    @Published var playlists: [Playlist] = []
    @Published var selectedPlaylist: Playlist?
    @Published var selectedTab: StreamType = .series
    @Published var selectedCategory: String = "All"
    @Published var categories: [String] = []
    @Published var displayedChannels: [Channel] = []
    @Published var favorites: [Channel] = []
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = ""
    
    // Track top channel for scroll logic
    @Published var topChannelId: String?
    
    private var repository: PrimeFlixRepository?
    
    init() { }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.loadPlaylists()
        self.loadFavorites()
    }
    
    func loadPlaylists() {
        guard let repo = repository else { return }
        self.playlists = repo.getAllPlaylists()
        if selectedPlaylist == nil, let first = playlists.first { selectPlaylist(first) }
    }
    
    func selectPlaylist(_ playlist: Playlist) {
        self.selectedPlaylist = playlist
        refreshContent()
    }
    
    func selectTab(_ tab: StreamType) {
        self.selectedTab = tab
        self.selectedCategory = "All"
        refreshContent()
    }
    
    func selectCategory(_ category: String) {
        self.selectedCategory = category
        loadChannels()
    }
    
    private func refreshContent() {
        loadGroups()
        loadChannels()
        loadFavorites()
    }
    
    private func loadGroups() {
        guard let repo = repository, let playlist = selectedPlaylist else { return }
        let rawGroups = repo.getGroups(playlistUrl: playlist.url, type: selectedTab)
        var smartList = ["All", "Favorites"]
        if selectedTab != .live { smartList.append("Recently Added") }
        smartList.append(contentsOf: rawGroups)
        self.categories = smartList
    }
    
    private func loadChannels() {
        guard let repo = repository, let playlist = selectedPlaylist else { return }
        self.isLoading = true
        self.loadingMessage = "Loading..."
        
        // Offload to background task to prevent UI freeze during deduplication
        Task {
            var channels: [Channel] = []
            
            switch selectedCategory {
            case "All":
                channels = repo.getBrowsingContent(playlistUrl: playlist.url, type: selectedTab, group: "All")
            case "Favorites":
                channels = favorites.filter { $0.type == selectedTab.rawValue }
            case "Recently Added":
                channels = repo.getRecentAdded(playlistUrl: playlist.url, type: selectedTab)
            default:
                channels = repo.getBrowsingContent(playlistUrl: playlist.url, type: selectedTab, group: selectedCategory)
            }
            
            await MainActor.run {
                self.displayedChannels = channels
                // Store first item ID for scroll-to-top logic
                self.topChannelId = channels.first?.url
                self.isLoading = false
            }
        }
    }
    
    private func loadFavorites() {
        guard let repo = repository else { return }
        self.favorites = repo.getFavorites()
    }
    
    func toggleFavorite(_ channel: Channel) {
        repository?.toggleFavorite(channel)
        loadFavorites()
        if selectedCategory == "Favorites" { loadChannels() }
    }
}
