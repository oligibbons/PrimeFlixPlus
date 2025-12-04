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
    @Published var isLoading: Bool = true // Start true by default
    @Published var backgroundUrl: URL?
    @Published var posterUrl: URL?
    @Published var backdropOpacity: Double = 0.0
    
    // --- Intelligent Versioning ---
    @Published var availableVersions: [Channel] = []
    @Published var selectedVersion: Channel?
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
    
    // Source map for playback
    private var episodeSourceMap: [String: String] = [:]
    
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    private var repository: PrimeFlixRepository?
    private let settings = SettingsViewModel()
    
    // MARK: - Structs
    
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
    }
    
    // MARK: - Async Loading (Non-Blocking)
    
    func loadData() async {
        // Ensure UI shows loading state immediately
        self.isLoading = true
        
        // 1. Fetch Versions in background
        if let repo = repository {
            self.availableVersions = repo.getVersions(for: channel)
            resolveBestVersion()
        }
        
        // 2. Parallel Data Fetching
        await withTaskGroup(of: Void.self) { group in
            // Task A: TMDB Data
            group.addTask { await self.fetchTmdbData() }
            
            // Task B: Series Data
            if self.channel.type == "series" {
                group.addTask { await self.fetchAggregatedSeriesData() }
            }
        }
        
        // 3. Reveal UI
        withAnimation(.easeIn(duration: 0.5)) {
            self.backdropOpacity = 1.0
            self.isLoading = false
        }
    }
    
    // MARK: - Smart Playback Logic
    
    func getSmartPlayTarget() -> Channel? {
        if channel.type == "movie" {
            return selectedVersion
        }
        
        if channel.type == "series" {
            // Find first unwatched or default to S1E1
            let sorted = xtreamEpisodes.sorted {
                if $0.season != $1.season { return $0.season < $1.season }
                return $0.episodeNum < $1.episodeNum
            }
            
            if let firstEp = sorted.first {
                return constructChannelForEpisode(firstEp)
            }
        }
        return nil
    }
    
    private func constructChannelForEpisode(_ ep: XtreamChannelInfo.Episode) -> Channel? {
        let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
        guard let sourceUrl = episodeSourceMap[key] else { return nil }
        
        let input = XtreamInput.decodeFromPlaylistUrl(sourceUrl)
        
        let safeUser = input.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? input.username
        let safePass = input.password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? input.password
        
        let streamUrl = "\(input.basicUrl)/series/\(safeUser)/\(safePass)/\(ep.id).m3u8"
        
        // Create Temp Core Data Object attached to the main context
        let ch = Channel(context: channel.managedObjectContext!)
        ch.url = streamUrl
        ch.title = "\(channel.title) - S\(ep.season)E\(ep.episodeNum)"
        ch.type = "series_episode"
        return ch
    }
    
    func createPlayableChannel(for episode: MergedEpisode) -> Channel {
        return constructChannelForEpisode(episode.streamInfo) ?? channel
    }
    
    // MARK: - Versioning
    
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
        if channel.type == "series" {
            Task { await fetchAggregatedSeriesData() }
        }
    }
    
    // MARK: - Watch History
    
    private func checkWatchHistory() {
        guard let repo = repository, let target = selectedVersion else { return }
        let context = repo.container.viewContext
        
        context.perform {
            let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            request.predicate = NSPredicate(format: "channelUrl == %@", target.url)
            request.fetchLimit = 1
            
            if let results = try? context.fetch(request), let progress = results.first {
                DispatchQueue.main.async {
                    self.resumePosition = Double(progress.position) / 1000.0
                    self.resumeDuration = Double(progress.duration) / 1000.0
                    let pct = self.resumePosition / self.resumeDuration
                    self.hasWatchHistory = pct > 0.02 && pct < 0.95
                }
            } else {
                DispatchQueue.main.async { self.hasWatchHistory = false }
            }
        }
    }
    
    // MARK: - Data Fetching
    
    private func fetchTmdbData() async {
        let title = channel.title
        let type = channel.type
        
        // Corrected: Removed invalid 'guard let' for non-optional return
        let info = await Task.detached(priority: .userInitiated) {
            return TitleNormalizer.parse(rawTitle: title)
        }.value
        
        do {
            if type == "series" {
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
    
    private func handleDetailsLoaded(_ details: TmdbDetails) {
        self.tmdbDetails = details
        if let bg = details.backdropPath {
            self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(bg)")
        }
        if let agg = details.aggregateCredits?.cast { self.cast = agg.prefix(12).map { $0 } }
        else if let creds = details.credits?.cast { self.cast = creds.prefix(12).map { $0 } }
    }
    
    // MARK: - Optimized Series Aggregation
    
    private func fetchAggregatedSeriesData() async {
        let versionsToFetch = availableVersions.isEmpty ? [channel] : availableVersions
        let client = self.xtreamClient
        
        // Corrected: Explicit return type for the detached task to solve ambiguous type error
        let result = await Task.detached(priority: .userInitiated) { () -> ([XtreamChannelInfo.Episode], [String: String], [Int]) in
            var allEpisodes: [(XtreamChannelInfo.Episode, String)] = []
            
            // Parallel Fetch for Versions
            await withTaskGroup(of: [(XtreamChannelInfo.Episode, String)].self) { group in
                for version in versionsToFetch {
                    group.addTask {
                        let input = XtreamInput.decodeFromPlaylistUrl(version.playlistUrl)
                        let seriesIdString = version.url.replacingOccurrences(of: "series://", with: "")
                        guard let seriesId = Int(seriesIdString) else { return [] }
                        
                        do {
                            let eps = try await client.getSeriesEpisodes(input: input, seriesId: seriesId)
                            return eps.map { ($0, version.playlistUrl) }
                        } catch {
                            return []
                        }
                    }
                }
                
                for await results in group {
                    allEpisodes.append(contentsOf: results)
                }
            }
            
            // Deduplication Logic
            var uniqueEpisodes: [String: (XtreamChannelInfo.Episode, String)] = [:]
            for (ep, source) in allEpisodes {
                let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
                if let existing = uniqueEpisodes[key] {
                    if ep.containerExtension == "mkv" && existing.0.containerExtension != "mkv" {
                        uniqueEpisodes[key] = (ep, source)
                    }
                } else {
                    uniqueEpisodes[key] = (ep, source)
                }
            }
            
            let finalEpisodes = uniqueEpisodes.values.map { $0.0 }
            let finalMap = uniqueEpisodes.mapValues { $0.1 }
            let finalSeasons = Set(finalEpisodes.map { $0.season }).sorted()
            
            return (finalEpisodes, finalMap, finalSeasons)
        }.value
        
        self.xtreamEpisodes = result.0
        self.episodeSourceMap = result.1
        self.seasons = result.2.isEmpty ? [1] : result.2
        
        if let first = self.seasons.first {
            await selectSeason(first)
        }
    }
    
    func selectSeason(_ season: Int) async {
        self.selectedSeason = season
        
        // Fetch TMDB Season Metadata (Lightweight)
        if tmdbEpisodes[season] == nil, let tmdbId = tmdbDetails?.id {
            if let seasonDetails = try? await tmdbClient.getTvSeason(tvId: tmdbId, seasonNumber: season) {
                tmdbEpisodes[season] = seasonDetails.episodes
            }
        }
        
        // Process Display Data in Background
        let xEps = self.xtreamEpisodes
        let tEps = self.tmdbEpisodes[season] ?? []
        let currentMap = self.episodeSourceMap
        let defaultPlaylist = self.channel.playlistUrl
        
        // Corrected: Explicit return type to prevent type inference errors
        let merged = await Task.detached(priority: .userInitiated) { () -> [MergedEpisode] in
            let seasonEpisodes = xEps.filter { $0.season == season }.sorted { $0.episodeNum < $1.episodeNum }
            
            return seasonEpisodes.map { xEp in
                let tEp = tEps.first(where: { $0.episodeNumber == xEp.episodeNum })
                let img = tEp?.stillPath.map { URL(string: "https://image.tmdb.org/t/p/w500\($0)")! }
                
                let key = String(format: "S%02dE%02d", xEp.season, xEp.episodeNum)
                let sourceUrl = currentMap[key] ?? defaultPlaylist
                
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
        }.value
        
        self.displayedEpisodes = merged
    }
    
    func toggleFavorite() {
        repository?.toggleFavorite(channel)
        self.isFavorite.toggle()
    }
}
