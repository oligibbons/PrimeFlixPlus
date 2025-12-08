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
    
    // --- Versioning ---
    struct VersionOption: Identifiable {
        let id: String
        let label: String
        let channel: Channel
        let score: Int
    }
    @Published var availableVersions: [VersionOption] = []
    @Published var selectedVersion: Channel?
    @Published var showVersionSelector: Bool = false
    
    // --- Smart Play ---
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
    private var episodeRegistry: [String: [EpisodeVersion]] = [:]
    
    // MARK: - Models
    
    struct EpisodeVersion: Identifiable {
        let id = UUID()
        let channel: Channel
        let qualityLabel: String
        let score: Int
    }
    
    struct MergedEpisode: Identifiable {
        let id: String // "S01E01"
        let season: Int
        let number: Int
        let title: String
        let overview: String
        let stillPath: URL?
        var versions: [EpisodeVersion]
        var isWatched: Bool = false
        var progress: Double = 0.0
        
        var displayTitle: String { "S\(season) • E\(number) - \(title)" }
        
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
        withAnimation { self.isLoading = false }
        withAnimation(.easeIn(duration: 0.5)) { self.backdropOpacity = 1.0 }
        
        let rawTitle = channel.canonicalTitle ?? channel.title
        let info = TitleNormalizer.parse(rawTitle: rawTitle)
        
        // --- 1. EPISODE INGESTION (Lazy Sync) ---
        if channel.type == "series" && channel.seriesId != nil && channel.seriesId != "0" {
            await ingestXtreamEpisodes(seriesId: channel.seriesId!)
        }
        
        // --- 2. FETCH VERSIONS (Core Data Aggregation) ---
        if channel.type == "series" || channel.type == "series_episode" {
            await fetchSeriesEcosystem(baseInfo: info)
        } else {
            await fetchMovieVersions()
        }
        
        // --- 3. TMDB METADATA ---
        await fetchTmdbData(title: info.normalizedTitle, type: channel.type)
        
        // --- 4. REFRESH UI ---
        if channel.type == "series" || channel.type == "series_episode" {
            await selectSeason(self.selectedSeason)
        }
        
        await recalculateSmartPlay()
    }
    
    // MARK: - The "Lazy Sync" Engine
    
    private func ingestXtreamEpisodes(seriesId: String) async {
        guard let repo = repository else { return }
        
        // Check if we already have episodes for this series ID to avoid re-fetching on every open
        let hasEpisodes: Bool = await Task.detached {
            let ctx = repo.container.newBackgroundContext()
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            req.predicate = NSPredicate(format: "seriesId == %@ AND type == 'series_episode'", seriesId)
            req.fetchLimit = 1
            return (try? ctx.count(for: req)) ?? 0 > 0
        }.value
        
        if hasEpisodes { return } // Cache hit, skip fetch
        
        // Fetch from API
        let input = XtreamInput.decodeFromPlaylistUrl(channel.playlistUrl)
        
        guard let episodes = try? await xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesId) else {
            print("❌ Failed to lazy-load episodes for Series \(seriesId)")
            return
        }
        
        // We use the Show's cover for episodes initially
        let showCover = self.channel.cover
        
        await Task.detached {
            let ctx = repo.container.newBackgroundContext()
            ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            // Map to Channel Entities (Dictionary Batch Insert)
            let objects = episodes.map { ep -> [String: Any] in
                // Note: We access local variable 'showCover' captured by closure, not self.channel
                let structItem = ChannelStruct.from(ep, seriesId: seriesId, playlistUrl: input.basicUrl, input: input, cover: showCover)
                return structItem.toDictionary()
            }
            
            let batchInsert = NSBatchInsertRequest(entity: Channel.entity(), objects: objects)
            _ = try? ctx.execute(batchInsert)
            try? ctx.save()
            print("✅ Lazy-loaded \(objects.count) episodes for Series \(seriesId)")
        }.value
    }
    
    // MARK: - Movie Logic
    
    private func fetchMovieVersions() async {
        guard let repo = repository else { return }
        let service = VersioningService(context: repo.container.viewContext)
        let rawVersions = service.getVersions(for: channel)
        
        self.availableVersions = rawVersions.map { ch in
            let raw = ch.canonicalTitle ?? ch.title
            let info = TitleNormalizer.parse(rawTitle: raw)
            var score = info.qualityScore
            if let lang = info.language, lang.lowercased().contains(settings.preferredLanguage.lowercased()) {
                score += 10000
            }
            let label = "\(info.language ?? "Unknown") | \(info.quality)"
            return VersionOption(id: ch.url, label: label, channel: ch, score: score)
        }.sorted { $0.score > $1.score }
        
        if let best = self.availableVersions.first {
            self.selectedVersion = best.channel
        }
    }
    
    func userSelectedVersion(_ channel: Channel) {
        self.selectedVersion = channel
        self.channel = channel
        self.showVersionSelector = false
    }
    
    // MARK: - Series Logic (Aggregation)
    
    private func fetchSeriesEcosystem(baseInfo: ContentInfo) async {
        guard let repo = repository else { return }
        
        let cleanTitle = baseInfo.normalizedTitle
        
        // FIX: Capture seriesId on MainActor BEFORE entering the background task.
        // This avoids the "await inside synchronous filter" error.
        let targetSeriesId = self.channel.seriesId
        
        // Fetch ALL candidate episodes from DB
        let allFiles: [Channel] = await Task.detached(priority: .userInitiated) {
            let ctx = repo.container.newBackgroundContext()
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            
            // 1. Strict ID Match (Xtream)
            if let sid = targetSeriesId, sid != "0" {
                req.predicate = NSPredicate(format: "seriesId == %@", sid)
            }
            // 2. Fallback: Fuzzy Name Match (M3U / Mixed Sources)
            else {
                req.predicate = NSPredicate(
                    format: "type == 'series_episode' AND title BEGINSWITH[cd] %@",
                    String(cleanTitle.prefix(4))
                )
            }
            
            let candidates = (try? ctx.fetch(req)) ?? []
            
            // Strict Filter for Name Match
            return candidates.filter { ch in
                // Strict ID Check (Thread-safe usage of captured 'targetSeriesId')
                if let sid = targetSeriesId, sid != "0", ch.seriesId == sid {
                    return true
                }
                
                // Fuzzy Fallback
                let info = TitleNormalizer.parse(rawTitle: ch.canonicalTitle ?? ch.title)
                return TitleNormalizer.similarity(between: cleanTitle, and: info.normalizedTitle) > 0.85
            }
        }.value
        
        // Grouping Logic
        var registry: [String: [EpisodeVersion]] = [:]
        var foundSeasons = Set<Int>()
        
        for file in allFiles {
            let s = Int(file.season)
            let e = Int(file.episode)
            
            if s == 0 && e == 0 { continue }
            
            let key = String(format: "S%02dE%02d", s, e)
            foundSeasons.insert(s)
            
            // Score
            let raw = file.canonicalTitle ?? file.title
            let info = TitleNormalizer.parse(rawTitle: raw)
            var score = info.qualityScore
            
            // Accessing settings on MainActor inside async context is tricky,
            // but we are currently on MainActor in 'fetchSeriesEcosystem' (async),
            // so we should capture preferences before loop if strict.
            // However, loop above was inside Task.detached. This loop is back on MainActor?
            // Wait, 'fetchSeriesEcosystem' is async but NOT isolated to Task yet.
            // The `allFiles` is awaited. So we are back on MainActor here. Safe.
            if let lang = info.language, lang.lowercased().contains(self.settings.preferredLanguage.lowercased()) {
                score += 10000
            }
            
            if file.seriesId != nil { score += 500 }
            
            let label = "\(info.language ?? "Default") \(info.quality)"
            let version = EpisodeVersion(channel: file, qualityLabel: label, score: score)
            
            registry[key, default: []].append(version)
        }
        
        // Sort versions
        for (key, _) in registry {
            registry[key]?.sort { $0.score > $1.score }
        }
        
        self.episodeRegistry = registry
        self.seasons = foundSeasons.sorted()
        
        if !self.seasons.contains(self.selectedSeason), let first = self.seasons.first {
            self.selectedSeason = first
        }
    }
    
    func selectSeason(_ season: Int) async {
        self.selectedSeason = season
        
        // Fetch TMDB data if missing
        if tmdbEpisodes[season] == nil, let tmdbId = tmdbDetails?.id {
            if let seasonDetails = try? await tmdbClient.getTvSeason(tvId: tmdbId, seasonNumber: season) {
                tmdbEpisodes[season] = seasonDetails.episodes
            }
        }
        
        var displayList: [MergedEpisode] = []
        let tmdbData = tmdbEpisodes[season] ?? []
        
        // Iterate Local Files
        let seasonPrefix = String(format: "S%02d", season)
        let localKeys = episodeRegistry.keys.filter { $0.hasPrefix(seasonPrefix) }
        let sortedKeys = localKeys.sorted()
        
        for key in sortedKeys {
            guard let versions = episodeRegistry[key] else { continue }
            let epNum = Int(key.suffix(2)) ?? 0
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
        } else if episode.getBestVersion() != nil {
            // Logic to trigger direct play is handled by the View's closure.
            // We just ensure we don't open the picker.
        }
    }
    
    // Added for Direct Play support
    @Published var directPlayChannel: Channel? = nil
    
    func triggerDirectPlay(_ episode: MergedEpisode) {
        if let best = episode.getBestVersion() {
            self.directPlayChannel = best.channel
        }
    }
    
    // MARK: - TMDB
    
    private func fetchTmdbData(title: String, type: String) async {
        let searchType = (type == "series" || type == "series_episode") ? "series" : "movie"
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
    
    private func updateProgressForDisplayedEpisodes() async {
        guard let repo = repository else { return }
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
        if let firstUnwatched = displayedEpisodes.first(where: { !$0.isWatched }) {
            self.smartPlayTarget = firstUnwatched
            self.playButtonLabel = "Continue S\(firstUnwatched.season) E\(firstUnwatched.number)"
        } else if let first = displayedEpisodes.first {
            self.smartPlayTarget = first
            self.playButtonLabel = "Start Series"
        }
    }
    
    private func checkWatchHistory() {
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
    
    func getPlayableChannel(version: EpisodeVersion, metadata: MergedEpisode) -> Channel {
        return version.channel
    }
    
    var similarContent: [TmdbMovieResult] {
        return tmdbDetails?.similar?.results.prefix(10).filter { $0.posterPath != nil } ?? []
    }
}
