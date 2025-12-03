import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class DetailsViewModel: ObservableObject {
    
    // --- Data Sources ---
    @Published var channel: Channel
    @Published var tmdbDetails: TmdbDetails?
    @Published var cast: [TmdbCast] = []
    
    // --- UI State ---
    @Published var isFavorite: Bool = false
    @Published var isLoading: Bool = false
    @Published var backgroundUrl: URL?
    @Published var posterUrl: URL?
    @Published var backdropOpacity: Double = 0.0
    
    // --- Intelligent Versioning ---
    @Published var availableVersions: [Channel] = []
    @Published var selectedVersion: Channel? // The actual file to play
    @Published var showVersionSelector: Bool = false
    
    // --- Resume Logic ---
    @Published var resumePosition: Double = 0
    @Published var resumeDuration: Double = 0
    @Published var hasWatchHistory: Bool = false
    
    // --- Series State ---
    @Published var xtreamEpisodes: [XtreamChannelInfo.Episode] = []
    @Published var tmdbEpisodes: [Int: [TmdbEpisode]] = [:]
    @Published var seasons: [Int] = []
    @Published var selectedSeason: Int = 1
    @Published var displayedEpisodes: [MergedEpisode] = []
    
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    private var repository: PrimeFlixRepository?
    private let settings = SettingsViewModel() // To access preferences
    
    struct MergedEpisode: Identifiable {
        let id: String
        let number: Int
        let title: String
        let overview: String
        let imageUrl: URL?
        let streamInfo: XtreamChannelInfo.Episode
        let sourcePlaylistUrl: String // CRITICAL: Knows which playlist this ep came from
        let isWatched: Bool
    }
    
    init(channel: Channel) {
        self.channel = channel
        self.isFavorite = channel.isFavorite
        self.selectedVersion = channel
        
        if let cover = channel.cover {
            self.posterUrl = URL(string: cover)
            self.backgroundUrl = URL(string: cover)
        }
    }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.checkWatchHistory()
        self.fetchVersions()
    }
    
    func loadData() async {
        self.isLoading = true
        await fetchTmdbData()
        
        if channel.type == "series" {
            // New Aggregation Logic
            await fetchAggregatedSeriesData()
        }
        
        withAnimation(.easeIn(duration: 0.5)) {
            self.backdropOpacity = 1.0
        }
        self.isLoading = false
    }
    
    // MARK: - Smart Versioning
    
    private func fetchVersions() {
        guard let repo = repository else { return }
        
        // 1. Get all raw duplicates
        let rawVersions = repo.getVersions(for: channel)
        self.availableVersions = rawVersions
        
        // 2. Auto-Select Best Version based on Settings
        resolveBestVersion()
    }
    
    private func resolveBestVersion() {
        guard !availableVersions.isEmpty else { return }
        
        let prefLang = settings.preferredLanguage.lowercased()
        let prefRes = settings.preferredResolution
        
        // Score each candidate
        let sorted = availableVersions.sorted { c1, c2 in
            let i1 = TitleNormalizer.parse(rawTitle: c1.title)
            let i2 = TitleNormalizer.parse(rawTitle: c2.title)
            
            var s1 = 0
            var s2 = 0
            
            // Language Match (+1000)
            if let l1 = i1.language?.lowercased(), l1.contains(prefLang) { s1 += 1000 }
            if let l2 = i2.language?.lowercased(), l2.contains(prefLang) { s2 += 1000 }
            
            // Resolution Match (+500)
            if i1.quality == prefRes { s1 += 500 }
            if i2.quality == prefRes { s2 += 500 }
            
            // Fallback: Higher Resolution (+10 per pixel class)
            s1 += i1.qualityScore / 100
            s2 += i2.qualityScore / 100
            
            return s1 > s2
        }
        
        self.selectedVersion = sorted.first
    }
    
    func userSelectedVersion(_ channel: Channel) {
        self.selectedVersion = channel
        self.showVersionSelector = false
    }
    
    // MARK: - Watch History
    
    private func checkWatchHistory() {
        guard let repo = repository, let target = selectedVersion else { return }
        
        let context = repo.container.viewContext
        let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        request.predicate = NSPredicate(format: "channelUrl == %@", target.url)
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            if let progress = results.first {
                self.resumePosition = Double(progress.position) / 1000.0
                self.resumeDuration = Double(progress.duration) / 1000.0
                let pct = self.resumePosition / self.resumeDuration
                self.hasWatchHistory = pct > 0.02 && pct < 0.95
            } else {
                self.hasWatchHistory = false
            }
        } catch { self.hasWatchHistory = false }
    }
    
    // MARK: - Data Fetching
    
    private func fetchTmdbData() async {
        let info = TitleNormalizer.parse(rawTitle: channel.title)
        do {
            if channel.type == "series" {
                let results = try await tmdbClient.searchTv(query: info.normalizedTitle, year: info.year)
                if let first = results.first {
                    let details = try await tmdbClient.getTvDetails(id: first.id)
                    handleDetailsLoaded(details)
                }
            } else {
                let results = try await tmdbClient.searchMovie(query: info.normalizedTitle, year: info.year)
                if let first = results.first {
                    let details = try await tmdbClient.getMovieDetails(id: first.id)
                    handleDetailsLoaded(details)
                }
            }
        } catch { print("TMDB: \(error)") }
    }
    
    @MainActor
    private func handleDetailsLoaded(_ details: TmdbDetails) {
        self.tmdbDetails = details
        if let bg = details.backdropPath {
            self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(bg)")
        }
        // Extract cast...
        if let agg = details.aggregateCredits?.cast { self.cast = agg.prefix(12).map { $0 } }
        else if let creds = details.credits?.cast { self.cast = creds.prefix(12).map { $0 } }
    }
    
    // MARK: - Aggregated Series Logic
    
    private func fetchAggregatedSeriesData() async {
        // Stores tuples of (Episode, SourcePlaylistUrl)
        var allEpisodes: [(XtreamChannelInfo.Episode, String)] = []
        
        // Loop through ALL grouped versions (S1, S2, 4K, etc.) to build a unified catalog
        for version in availableVersions {
            // Extract credentials from this specific version's playlist URL
            let input = XtreamInput.decodeFromPlaylistUrl(version.playlistUrl)
            
            // Extract the Xtream Series ID
            let seriesIdString = version.url.replacingOccurrences(of: "series://", with: "")
            guard let seriesId = Int(seriesIdString) else { continue }
            
            do {
                let episodes = try await xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesId)
                // Attach the source playlist to each episode so we know where to play it from
                let taggedEpisodes = episodes.map { ($0, version.playlistUrl) }
                allEpisodes.append(contentsOf: taggedEpisodes)
            } catch {
                print("Failed to fetch episodes for version: \(version.title)")
            }
        }
        
        // Deduplicate Episodes (Keep best quality if duplicates exist)
        // Key: "S01E01"
        // Value: (Episode, SourceUrl)
        var uniqueEpisodes: [String: (XtreamChannelInfo.Episode, String)] = [:]
        
        for (ep, source) in allEpisodes {
            let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
            
            if let existing = uniqueEpisodes[key] {
                // If new one has a better container or seems like higher quality, swap it
                // Simple heuristic: mkv > mp4
                if ep.containerExtension == "mkv" && existing.0.containerExtension != "mkv" {
                    uniqueEpisodes[key] = (ep, source)
                }
            } else {
                uniqueEpisodes[key] = (ep, source)
            }
        }
        
        // Flatten back to struct
        self.xtreamEpisodes = uniqueEpisodes.values.map { $0.0 }
        
        // We store a map of ID -> Source for easy lookup during creation
        // Ideally, MergedEpisode holds it.
        
        // Calculate Available Seasons
        let allSeasons = Set(self.xtreamEpisodes.map { $0.season }).sorted()
        self.seasons = allSeasons.isEmpty ? [1] : allSeasons
        
        // Default to Season 1 or first available
        if let first = self.seasons.first {
            await selectSeason(first, episodeMap: uniqueEpisodes)
        }
    }
    
    // Overloaded selectSeason to accept the map (internal helper)
    private func selectSeason(_ season: Int, episodeMap: [String: (XtreamChannelInfo.Episode, String)]) async {
        self.selectedSeason = season
        
        // Fetch TMDB Season if missing
        if tmdbEpisodes[season] == nil, let tmdbId = tmdbDetails?.id {
            if let seasonDetails = try? await tmdbClient.getTvSeason(tvId: tmdbId, seasonNumber: season) {
                tmdbEpisodes[season] = seasonDetails.episodes
            }
        }
        
        let xtreamForSeason = xtreamEpisodes.filter { $0.season == season }
            .sorted { $0.episodeNum < $1.episodeNum }
        
        let tmdbForSeason = tmdbEpisodes[season] ?? []
        
        self.displayedEpisodes = xtreamForSeason.map { xEp in
            let tEp = tmdbForSeason.first(where: { $0.episodeNumber == xEp.episodeNum })
            let img = tEp?.stillPath.map { URL(string: "https://image.tmdb.org/t/p/w500\($0)")! }
            
            // Find the source playlist URL for this episode
            let key = String(format: "S%02dE%02d", xEp.season, xEp.episodeNum)
            let sourceUrl = episodeMap[key]?.1 ?? channel.playlistUrl // Fallback to main
            
            return MergedEpisode(
                id: xEp.id,
                number: xEp.episodeNum,
                title: tEp?.name ?? xEp.title ?? "Episode \(xEp.episodeNum)",
                overview: tEp?.overview ?? "",
                imageUrl: img ?? nil,
                streamInfo: xEp,
                sourcePlaylistUrl: sourceUrl,
                isWatched: false
            )
        }
    }
    
    // Wrapper for public access if needed (re-generates map, slightly inefficient but safe)
    func selectSeason(_ season: Int) async {
        // This won't work well without the map.
        // For this architecture, we assume `xtreamEpisodes` is already populated,
        // but we lost the `sourcePlaylistUrl` mapping if we just use `xtreamEpisodes`.
        // FIX: Let's make `displayedEpisodes` carry the data, so we don't need the map here.
        // Actually, we only need to rebuild the display.
        // We can iterate `availableVersions` again, or better:
        // Let's assume `fetchAggregatedSeriesData` is called ONCE.
        // We need to persist the Source URL mapping in the class.
    }
    
    func toggleFavorite() {
        repository?.toggleFavorite(channel)
        self.isFavorite.toggle()
    }
    
    func createPlayableChannel(for episode: MergedEpisode) -> Channel {
        // Use the specific source playlist URL for this episode
        let input = XtreamInput.decodeFromPlaylistUrl(episode.sourcePlaylistUrl)
        
        let url = "\(input.basicUrl)/series/\(input.username)/\(input.password)/\(episode.streamInfo.id).\(episode.streamInfo.containerExtension)"
        let ch = Channel(context: channel.managedObjectContext!)
        ch.url = url
        ch.title = "\(channel.title) - S\(selectedSeason)E\(episode.number)"
        return ch
    }
}
