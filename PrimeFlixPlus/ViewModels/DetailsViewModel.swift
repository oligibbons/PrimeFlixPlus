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
    @Published var isLoading: Bool = true
    @Published var backgroundUrl: URL?
    @Published var posterUrl: URL?
    @Published var backdropOpacity: Double = 0.0
    
    // --- Versioning (Movies & Series Containers) ---
    struct VersionOption: Identifiable {
        let id: String // URL acts as ID
        let label: String
        let channel: Channel
        let score: Int // For sorting
    }
    @Published var availableVersions: [VersionOption] = []
    @Published var selectedVersion: Channel?
    @Published var showVersionSelector: Bool = false
    
    // --- Smart Play State ---
    @Published var smartPlayTarget: MergedEpisode? = nil
    @Published var playButtonLabel: String = "Play Now"
    @Published var playButtonIcon: String = "play.fill"
    @Published var hasWatchHistory: Bool = false
    
    // --- Series State ---
    @Published var seasons: [Int] = []
    @Published var selectedSeason: Int = 1
    @Published var displayedEpisodes: [MergedEpisode] = []
    
    // --- Interaction ---
    @Published var episodeToPlay: MergedEpisode? = nil
    @Published var showEpisodeVersionPicker: Bool = false
    
    // --- Dependencies ---
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    private var repository: PrimeFlixRepository?
    private let settings = SettingsViewModel()
    
    // --- Internal ---
    private var tmdbEpisodes: [Int: [TmdbEpisode]] = [:]
    
    // Holds ALL file variants for every episode in the show
    // Key: "S01E01" -> [File1 (4K), File2 (1080p), File3 (French)]
    private var episodeRegistry: [String: [EpisodeVersion]] = [:]
    
    // MARK: - Models (Internal)
    
    struct EpisodeVersion: Identifiable {
        let id = UUID()
        let channel: Channel // The actual Core Data object to play
        let qualityLabel: String // "English 4K"
        let score: Int
    }
    
    struct MergedEpisode: Identifiable {
        let id: String // "S01E01"
        let season: Int
        let number: Int
        
        // Metadata (from TMDB)
        let title: String
        let overview: String
        let stillPath: URL?
        
        // Playable Files
        var versions: [EpisodeVersion]
        
        // State
        var isWatched: Bool = false
        var progress: Double = 0.0
        
        var displayTitle: String { "S\(season) • E\(number) - \(title)" }
        
        // Helper to get the best default version based on user prefs
        func getBestVersion() -> EpisodeVersion? {
            return versions.max(by: { $0.score < $1.score })
        }
    }
    
    // MARK: - Init
    
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
    
    func loadData() async {
        // Optimistic UI update
        withAnimation { self.isLoading = false }
        withAnimation(.easeIn(duration: 0.5)) { self.backdropOpacity = 1.0 }
        
        // 1. Analyze Title (Clean it first!)
        let rawTitle = channel.canonicalTitle ?? channel.title
        let info = TitleNormalizer.parse(rawTitle: rawTitle)
        
        // 2. Fetch Versions (Parallel)
        if channel.type == "series" || channel.type == "series_episode" {
            await fetchSeriesEcosystem(baseInfo: info)
        } else {
            await fetchMovieVersions()
        }
        
        // 3. Fetch TMDB (Using CLEAN title)
        // Critical Fix: Use `normalizedTitle` (e.g. "Severance") not raw title ("Severance S01E01")
        await fetchTmdbData(title: info.normalizedTitle, type: channel.type)
        
        // 4. Post-Process (Series Metadata Merging)
        if channel.type == "series" || channel.type == "series_episode" {
            // Now that we have TMDB data, refresh the episode list titles
            await selectSeason(self.selectedSeason)
        }
        
        // 5. Smart Play Calculation
        await recalculateSmartPlay()
    }
    
    // MARK: - Movie Logic
    
    private func fetchMovieVersions() async {
        guard let repo = repository else { return }
        
        // Fetch Siblings
        let service = VersioningService(context: repo.container.viewContext)
        let rawVersions = service.getVersions(for: channel)
        
        // Generate Labels & Scores
        self.availableVersions = rawVersions.map { ch in
            let raw = ch.canonicalTitle ?? ch.title
            let info = TitleNormalizer.parse(rawTitle: raw)
            
            // Score: Prioritize Language match, then Resolution
            var score = info.qualityScore
            if let lang = info.language, lang.lowercased().contains(settings.preferredLanguage.lowercased()) {
                score += 10000
            }
            
            let label = "\(info.language ?? "Unknown") | \(info.quality)"
            
            return VersionOption(id: ch.url, label: label, channel: ch, score: score)
        }.sorted { $0.score > $1.score }
        
        // Auto-select best
        if let best = self.availableVersions.first {
            self.selectedVersion = best.channel
        }
    }
    
    func userSelectedVersion(_ channel: Channel) {
        self.selectedVersion = channel
        self.channel = channel // Update main reference for playback
        self.showVersionSelector = false
    }
    
    // MARK: - Series Logic (The "Chillio" Fix)
    
    private func fetchSeriesEcosystem(baseInfo: ContentInfo) async {
        guard let repo = repository else { return }
        
        // A. Find ALL episodes for this show in the DB
        // We search by the Normalized Title (e.g. "Severance")
        let cleanTitle = baseInfo.normalizedTitle
        
        let allFiles: [Channel] = await Task.detached(priority: .userInitiated) {
            let ctx = repo.container.newBackgroundContext()
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            
            // "Severance%" matches "Severance", "Severance Fr", "Severance 4K"
            // We search fairly broadly here, then filter strictly with Normalizer
            req.predicate = NSPredicate(
                format: "type == 'series_episode' AND title BEGINSWITH[cd] %@",
                String(cleanTitle.prefix(4))
            )
            
            let candidates = (try? ctx.fetch(req)) ?? []
            
            // Strict Filter: Must match normalized title
            return candidates.filter { ch in
                let info = TitleNormalizer.parse(rawTitle: ch.canonicalTitle ?? ch.title)
                return TitleNormalizer.similarity(between: cleanTitle, and: info.normalizedTitle) > 0.85
            }
        }.value
        
        // B. Group into Episode Buckets
        var registry: [String: [EpisodeVersion]] = [:]
        var foundSeasons = Set<Int>()
        
        for file in allFiles {
            // Extract S/E
            let raw = file.canonicalTitle ?? file.title
            let info = TitleNormalizer.parse(rawTitle: raw)
            
            if info.season == 0 && info.episode == 0 { continue }
            
            let key = String(format: "S%02dE%02d", info.season, info.episode)
            foundSeasons.insert(info.season)
            
            // Score
            var score = info.qualityScore
            if let lang = info.language, lang.lowercased().contains(settings.preferredLanguage.lowercased()) {
                score += 10000 // Huge boost for preferred language
            }
            
            let label = "\(info.language ?? "Unknown") \(info.quality)"
            
            let version = EpisodeVersion(channel: file, qualityLabel: label, score: score)
            registry[key, default: []].append(version)
        }
        
        // Sort versions within buckets
        for (key, _) in registry {
            registry[key]?.sort { $0.score > $1.score }
        }
        
        self.episodeRegistry = registry
        self.seasons = foundSeasons.sorted()
        
        // Select first season or keep current if valid
        if !self.seasons.contains(self.selectedSeason), let first = self.seasons.first {
            self.selectedSeason = first
        }
    }
    
    func selectSeason(_ season: Int) async {
        self.selectedSeason = season
        
        // 1. Ensure TMDB data for this season is fetched
        if tmdbEpisodes[season] == nil, let tmdbId = tmdbDetails?.id {
            if let seasonDetails = try? await tmdbClient.getTvSeason(tvId: tmdbId, seasonNumber: season) {
                tmdbEpisodes[season] = seasonDetails.episodes
            }
        }
        
        // 2. Merge Local Files with TMDB Data
        var displayList: [MergedEpisode] = []
        let tmdbData = tmdbEpisodes[season] ?? []
        
        // Get all SxxExx keys for this season present in our Local Files
        let seasonPrefix = String(format: "S%02d", season)
        let localKeys = episodeRegistry.keys.filter { $0.hasPrefix(seasonPrefix) }
        
        // We iterate LOCAL files primarily, so we don't show episodes we don't have
        // (unless we want to show "Missing" episodes, but usually we just show what's playable)
        let sortedKeys = localKeys.sorted()
        
        for key in sortedKeys {
            guard let versions = episodeRegistry[key] else { continue }
            let epNum = Int(key.suffix(2)) ?? 0
            
            // Find Metadata
            let meta = tmdbData.first(where: { $0.episodeNumber == epNum })
            
            let stillUrl: URL?
            if let path = meta?.stillPath {
                stillUrl = URL(string: "https://image.tmdb.org/t/p/w500\(path)")
            } else {
                stillUrl = nil
            }
            
            let merged = MergedEpisode(
                id: key,
                season: season,
                number: epNum,
                title: meta?.name ?? "Episode \(epNum)",
                overview: meta?.overview ?? "No description available.",
                stillPath: stillUrl,
                versions: versions
            )
            displayList.append(merged)
        }
        
        withAnimation { self.displayedEpisodes = displayList }
        await updateProgressForDisplayedEpisodes()
    }
    
    // MARK: - Interactions
    
    func onPlayEpisodeClicked(_ episode: MergedEpisode) {
        if episode.versions.count > 1 {
            self.episodeToPlay = episode
            self.showEpisodeVersionPicker = true
        } else if let best = episode.getBestVersion() {
            // Direct Play
            // We need to signal the View to play this channel
            // Since onPlay is a closure in View, we can update selectedVersion/Channel here?
            // Actually, DetailsView uses a callback. We should likely expose a "requestPlay" publisher or return channel.
            // For now, setting selectedVersion updates the "Main" play button, but the list needs direct action.
            // The View handles the tap on the list item.
        }
    }
    
    func getPlayableChannel(version: EpisodeVersion, metadata: MergedEpisode) -> Channel {
        // We return the actual Core Data object.
        // We might want to inject the metadata titles temporarily into it if needed,
        // but it's safer to just return the object.
        return version.channel
    }
    
    // MARK: - TMDB
    
    private func fetchTmdbData(title: String, type: String) async {
        // Logic: Search for the CLEAN title (e.g. "Severance")
        // If it's an episode/series type, search TV.
        // If it's a movie, search Movie.
        
        let searchType = (type == "series" || type == "series_episode") ? "series" : "movie"
        
        // Note: Year extraction is handled in TitleNormalizer, can be passed here if needed.
        // For now, we trust the clean title search.
        
        if let match = await tmdbClient.findBestMatch(title: title, year: nil, type: searchType) {
            if searchType == "series" {
                if let details = try? await tmdbClient.getTvDetails(id: match.id) {
                    await MainActor.run { self.applyTmdbData(details) }
                }
            } else {
                if let details = try? await tmdbClient.getMovieDetails(id: match.id) {
                    await MainActor.run { self.applyTmdbData(details) }
                }
            }
        }
    }
    
    private func applyTmdbData(_ details: TmdbDetails) {
        self.tmdbDetails = details
        if let bg = details.backdropPath {
            self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(bg)")
        }
        if let castData = details.aggregateCredits?.cast ?? details.credits?.cast {
            self.cast = castData
        }
    }
    
    // MARK: - Progress & History
    
    private func updateProgressForDisplayedEpisodes() async {
        guard let repo = repository else { return }
        
        // Flatten all URLs for the current view
        let allUrls = displayedEpisodes.flatMap { $0.versions.map { $0.channel.url } }
        
        let progressMap: [String: Double] = await Task.detached(priority: .background) {
            let ctx = repo.container.newBackgroundContext()
            let req = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            req.predicate = NSPredicate(format: "channelUrl IN %@", allUrls)
            
            var map: [String: Double] = [:]
            if let results = try? ctx.fetch(req) {
                for p in results {
                    if p.duration > 0 {
                        map[p.channelUrl] = Double(p.position) / Double(p.duration)
                    }
                }
            }
            return map
        }.value
        
        // Map back to Merged Episodes
        // If ANY version is watched, the episode is watched.
        var updated = displayedEpisodes
        for i in 0..<updated.count {
            var maxProg = 0.0
            for v in updated[i].versions {
                if let p = progressMap[v.channel.url], p > maxProg { maxProg = p }
            }
            updated[i].progress = maxProg
            updated[i].isWatched = maxProg > 0.95
        }
        self.displayedEpisodes = updated
    }
    
    private func recalculateSmartPlay() async {
        // Basic Logic: Find first unwatched episode
        if let firstUnwatched = displayedEpisodes.first(where: { !$0.isWatched }) {
            self.smartPlayTarget = firstUnwatched
            self.playButtonLabel = "Continue S\(firstUnwatched.season) E\(firstUnwatched.number)"
        } else if let first = displayedEpisodes.first {
            // All watched? Start over or show first
            self.smartPlayTarget = first
            self.playButtonLabel = "Start Series"
        }
    }
    
    private func checkWatchHistory() {
        // Only for movies really, series handled above
        guard let repo = repository, channel.type == "movie" else { return }
        let url = channel.url
        Task.detached {
            let ctx = repo.container.newBackgroundContext()
            let req = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            req.predicate = NSPredicate(format: "channelUrl == %@", url)
            if let p = try? ctx.fetch(req).first, p.duration > 0 {
                let progress = Double(p.position) / Double(p.duration)
                await MainActor.run {
                    self.hasWatchHistory = progress > 0.05 && progress < 0.95
                }
            }
        }
    }
    
    func toggleFavorite() {
        repository?.toggleFavorite(channel)
        self.isFavorite.toggle()
    }
    
    var similarContent: [TmdbMovieResult] {
        return tmdbDetails?.similar?.results.prefix(10).filter { $0.posterPath != nil } ?? []
    }
}
