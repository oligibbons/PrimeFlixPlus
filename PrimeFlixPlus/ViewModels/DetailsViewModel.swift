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
    @Published var selectedVersion: Channel? // The actual file (or Series parent)
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
    
    // CRITICAL: Maps "S01E01" -> "PlaylistURL" to recover credentials for playback
    private var episodeSourceMap: [String: String] = [:]
    
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    private var repository: PrimeFlixRepository?
    private let settings = SettingsViewModel()
    
    struct MergedEpisode: Identifiable {
        let id: String
        let number: Int
        let title: String
        let overview: String
        let imageUrl: URL?
        let streamInfo: XtreamChannelInfo.Episode
        let sourcePlaylistUrl: String
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
            await fetchAggregatedSeriesData()
        }
        
        withAnimation(.easeIn(duration: 0.5)) {
            self.backdropOpacity = 1.0
        }
        self.isLoading = false
    }
    
    // MARK: - Smart Playback Logic
    
    /// Determines exactly what file to play when the user hits "Play".
    /// For Movies: Returns the movie file.
    /// For Series: Returns the First Episode (S1E1) or the Resume Point.
    func getSmartPlayTarget() -> Channel? {
        // 1. Movies are simple: just play the file
        if channel.type == "movie" {
            return selectedVersion
        }
        
        // 2. Series: We NEVER play the 'series://' URL. We must find an episode.
        if channel.type == "series" {
            // A. Sort all episodes to find the first one
            let sorted = xtreamEpisodes.sorted {
                if $0.season != $1.season { return $0.season < $1.season }
                return $0.episodeNum < $1.episodeNum
            }
            
            // B. TODO: Add Resume Logic here (find first unwatched)
            // For now, default to S1 E1
            if let firstEp = sorted.first {
                return constructChannelForEpisode(firstEp)
            }
        }
        
        return nil
    }
    
    /// Helper to build a temporary Channel object for a specific episode
    private func constructChannelForEpisode(_ ep: XtreamChannelInfo.Episode) -> Channel? {
        let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
        guard let sourceUrl = episodeSourceMap[key] else { return nil }
        
        // Decode credentials from the specific playlist that provided this episode
        let input = XtreamInput.decodeFromPlaylistUrl(sourceUrl)
        
        // 1. Strict Encoding for Credentials
        // Special characters in passwords (e.g., "pass@word") break the URL path if not encoded.
        let safeUser = input.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? input.username
        let safePass = input.password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? input.password
        
        // 2. THE FIX: Force .m3u8 extension
        // This tells the Xtream server to stream via HLS, which is native to Apple TV.
        // It bypasses the MKV incompatibility and usually fixes 404 errors on the /series/ endpoint.
        let streamUrl = "\(input.basicUrl)/series/\(safeUser)/\(safePass)/\(ep.id).m3u8"
        
        // Create Temp Core Data Object
        let ch = Channel(context: channel.managedObjectContext!)
        ch.url = streamUrl
        ch.title = "\(channel.title) - S\(ep.season)E\(ep.episodeNum)"
        ch.type = "series_episode" // Marker type
        return ch
    }
    
    // Only used when clicking a specific episode card
    func createPlayableChannel(for episode: MergedEpisode) -> Channel {
        return constructChannelForEpisode(episode.streamInfo) ?? channel
    }
    
    // MARK: - Smart Versioning
    
    private func fetchVersions() {
        guard let repo = repository else { return }
        let rawVersions = repo.getVersions(for: channel)
        self.availableVersions = rawVersions
        resolveBestVersion()
    }
    
    private func resolveBestVersion() {
        guard !availableVersions.isEmpty else { return }
        let prefLang = settings.preferredLanguage.lowercased()
        let prefRes = settings.preferredResolution
        
        let sorted = availableVersions.sorted { c1, c2 in
            let i1 = TitleNormalizer.parse(rawTitle: c1.title)
            let i2 = TitleNormalizer.parse(rawTitle: c2.title)
            var s1 = 0; var s2 = 0
            
            if let l1 = i1.language?.lowercased(), l1.contains(prefLang) { s1 += 1000 }
            if let l2 = i2.language?.lowercased(), l2.contains(prefLang) { s2 += 1000 }
            if i1.quality == prefRes { s1 += 500 }
            if i2.quality == prefRes { s2 += 500 }
            s1 += i1.qualityScore / 100
            s2 += i2.qualityScore / 100
            return s1 > s2
        }
        self.selectedVersion = sorted.first
    }
    
    func userSelectedVersion(_ channel: Channel) {
        self.selectedVersion = channel
        self.showVersionSelector = false
        // Re-fetch series data if we switched versions (providers might differ)
        if channel.type == "series" {
            Task { await fetchAggregatedSeriesData() }
        }
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
            } else { self.hasWatchHistory = false }
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
        } catch { print("TMDB Error: \(error)") }
    }
    
    @MainActor
    private func handleDetailsLoaded(_ details: TmdbDetails) {
        self.tmdbDetails = details
        if let bg = details.backdropPath {
            self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(bg)")
        }
        if let agg = details.aggregateCredits?.cast { self.cast = agg.prefix(12).map { $0 } }
        else if let creds = details.credits?.cast { self.cast = creds.prefix(12).map { $0 } }
    }
    
    // MARK: - Aggregated Series Logic
    
    private func fetchAggregatedSeriesData() async {
        var allEpisodes: [(XtreamChannelInfo.Episode, String)] = []
        
        let versionsToFetch = availableVersions.isEmpty ? [channel] : availableVersions
        
        for version in versionsToFetch {
            let input = XtreamInput.decodeFromPlaylistUrl(version.playlistUrl)
            let seriesIdString = version.url.replacingOccurrences(of: "series://", with: "")
            guard let seriesId = Int(seriesIdString) else { continue }
            
            do {
                let episodes = try await xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesId)
                let tagged = episodes.map { ($0, version.playlistUrl) }
                allEpisodes.append(contentsOf: tagged)
            } catch {
                print("Failed episodes fetch: \(version.title)")
            }
        }
        
        // 2. Deduplicate & Populate Source Map
        var uniqueEpisodes: [String: (XtreamChannelInfo.Episode, String)] = [:]
        
        for (ep, source) in allEpisodes {
            let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
            
            // Logic: Prefer MKV/Better extensions if duplicate
            if let existing = uniqueEpisodes[key] {
                if ep.containerExtension == "mkv" && existing.0.containerExtension != "mkv" {
                    uniqueEpisodes[key] = (ep, source)
                }
            } else {
                uniqueEpisodes[key] = (ep, source)
            }
        }
        
        // 3. Save to State
        self.xtreamEpisodes = uniqueEpisodes.values.map { $0.0 }
        
        // CRITICAL: Save the map so `constructChannelForEpisode` works!
        self.episodeSourceMap = uniqueEpisodes.mapValues { $0.1 }
        
        // 4. Update UI
        let allSeasons = Set(self.xtreamEpisodes.map { $0.season }).sorted()
        self.seasons = allSeasons.isEmpty ? [1] : allSeasons
        
        if let first = self.seasons.first {
            await selectSeason(first)
        }
    }
    
    func selectSeason(_ season: Int) async {
        self.selectedSeason = season
        
        // Fetch TMDB Season Metadata
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
            
            let key = String(format: "S%02dE%02d", xEp.season, xEp.episodeNum)
            let sourceUrl = episodeSourceMap[key] ?? channel.playlistUrl
            
            return MergedEpisode(
                id: xEp.id,
                number: xEp.episodeNum,
                title: tEp?.name ?? xEp.title ?? "Episode \(xEp.episodeNum)",
                overview: tEp?.overview ?? "",
                imageUrl: img,
                streamInfo: xEp,
                sourcePlaylistUrl: sourceUrl,
                isWatched: false
            )
        }
    }
    
    func toggleFavorite() {
        repository?.toggleFavorite(channel)
        self.isFavorite.toggle()
    }
}
