import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class DetailsViewModel: ObservableObject {
    
    // --- Data Sources ---
    @Published var channel: Channel
    @Published var tmdbDetails: TmdbDetails? // Kept for Movies
    @Published var omdbDetails: OmdbSeriesDetails? // NEW: For Series
    @Published var cast: [TmdbCast] = []
    
    // --- UI State ---
    @Published var isFavorite: Bool = false
    @Published var isLoading: Bool = true
    @Published var backgroundUrl: URL?
    @Published var posterUrl: URL?
    @Published var backdropOpacity: Double = 0.0
    
    // --- Extra Ratings (OMDB) ---
    @Published var externalRatings: [OmdbRating] = []
    
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
    @Published var directPlayChannel: Channel? = nil
    
    // --- Dependencies ---
    private let tmdbClient = TmdbClient()
    private let omdbClient = OmdbClient() // NEW
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
        self.isLoading = true // Force loading state
        
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
        
        // --- 3. METADATA STRATEGY ---
        if channel.type == "series" || channel.type == "series_episode" {
            // Use OMDB for Series
            await fetchOmdbSeriesData(title: info.normalizedTitle, year: info.year)
        } else {
            // Use TMDB for Movies (as it works perfectly)
            await fetchTmdbMovieData(title: info.normalizedTitle)
        }
        
        // --- 4. REFRESH UI ---
        if channel.type == "series" || channel.type == "series_episode" {
            await selectSeason(self.selectedSeason)
        }
        
        await recalculateSmartPlay()
        
        // Reveal UI
        withAnimation { self.isLoading = false }
        withAnimation(.easeIn(duration: 0.5)) { self.backdropOpacity = 1.0 }
    }
    
    // MARK: - OMDB Logic (New)
    
    private func fetchOmdbSeriesData(title: String, year: String?) async {
        // 1. Check Local Cache (MediaMetadata via Title Hash)
        // Since we don't have a clean IMDB ID stored yet, we hash the title.
        let titleHash = String(title.lowercased().hashValue)
        
        if let cached = fetchFromCoreData(titleHash: titleHash) {
            print("✅ Loaded Series Metadata from Core Data Cache")
            applyMetadata(cached)
            return
        }
        
        // 2. Fetch from API
        print("🌍 Fetching OMDB Series Data for: \(title)")
        if let details = await omdbClient.getSeriesMetadata(title: title, year: year) {
            
            // 3. Update UI
            await MainActor.run {
                self.omdbDetails = details
                self.externalRatings = details.ratings ?? []
                self.channel.overview = details.plot
                
                // Update Cover if missing
                if self.channel.cover == nil, let poster = details.poster, poster.hasPrefix("http") {
                    self.channel.cover = poster
                    self.posterUrl = URL(string: poster)
                    // Use poster as backdrop for series if no better option
                    if self.backgroundUrl == nil { self.backgroundUrl = URL(string: poster) }
                }
            }
            
            // 4. Save to Core Data (Cache)
            saveToCoreData(details: details, titleHash: titleHash, title: title)
        }
    }
    
    private func fetchFromCoreData(titleHash: String) -> MediaMetadata? {
        guard let ctx = repository?.container.viewContext else { return nil }
        let req = NSFetchRequest<MediaMetadata>(entityName: "MediaMetadata")
        req.predicate = NSPredicate(format: "normalizedTitleHash == %@", titleHash)
        req.fetchLimit = 1
        return try? ctx.fetch(req).first
    }
    
    private func saveToCoreData(details: OmdbSeriesDetails, titleHash: String, title: String) {
        guard let repo = repository else { return }
        
        // Perform on background to avoid UI hitch
        repo.container.performBackgroundTask { context in
            let req = NSFetchRequest<MediaMetadata>(entityName: "MediaMetadata")
            req.predicate = NSPredicate(format: "normalizedTitleHash == %@", titleHash)
            
            let meta: MediaMetadata
            if let existing = try? context.fetch(req).first {
                meta = existing
            } else {
                meta = MediaMetadata(context: context)
                meta.normalizedTitleHash = titleHash
            }
            
            meta.title = details.title
            meta.overview = details.plot
            meta.posterPath = details.poster
            // We store the IMDB ID in the overview or a separate field if we had one.
            // For now, this is enough to cache the expensive fetch.
            meta.lastUpdated = Date()
            
            // Hack: Store ratings in overview? No, better not mess it up.
            // We rely on OMDB Client memory cache for ratings during session,
            // and this Core Data cache for the heavy lifting of text/images.
            
            try? context.save()
        }
    }
    
    private func applyMetadata(_ meta: MediaMetadata) {
        self.channel.overview = meta.overview
        if let p = meta.posterPath {
            self.channel.cover = p
            self.posterUrl = URL(string: p)
            if self.backgroundUrl == nil { self.backgroundUrl = URL(string: p) }
        }
    }

    // MARK: - TMDB Logic (Movies Only)
    
    private func fetchTmdbMovieData(title: String) async {
        if let match = await tmdbClient.findBestMatch(title: title, year: nil, type: "movie") {
            if let details = try? await tmdbClient.getMovieDetails(id: match.id) {
                await MainActor.run { self.applyTmdbData(details) }
            }
        }
    }
    
    private func applyTmdbData(_ details: TmdbDetails) {
        self.tmdbDetails = details
        if let bg = details.backdropPath {
            self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(bg)")
        }
        if let castData = details.credits?.cast {
            self.cast = castData
        }
    }
    
    // MARK: - Lazy Sync (Episodes)
    
    private func ingestXtreamEpisodes(seriesId: String) async {
        guard let repo = repository else { return }
        
        let hasEpisodes: Bool = await Task.detached {
            let ctx = repo.container.newBackgroundContext()
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            req.predicate = NSPredicate(format: "seriesId == %@ AND type == 'series_episode'", seriesId)
            req.fetchLimit = 1
            return (try? ctx.count(for: req)) ?? 0 > 0
        }.value
        
        if hasEpisodes { return }
        
        let input = XtreamInput.decodeFromPlaylistUrl(channel.playlistUrl)
        
        // Added visual feedback in UI via 'isLoading'
        
        guard let episodes = try? await xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesId) else {
            print("❌ Failed to lazy-load episodes for Series \(seriesId)")
            return
        }
        
        // Capture show cover for the background task
        let showCover = self.channel.cover
        
        await Task.detached {
            let ctx = repo.container.newBackgroundContext()
            ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            let objects = episodes.map { ep -> [String: Any] in
                let structItem = ChannelStruct.from(ep, seriesId: seriesId, playlistUrl: input.basicUrl, input: input, cover: showCover)
                return structItem.toDictionary()
            }
            
            let batchInsert = NSBatchInsertRequest(entity: Channel.entity(), objects: objects)
            _ = try? ctx.execute(batchInsert)
            try? ctx.save()
            print("✅ Lazy-loaded \(objects.count) episodes for Series \(seriesId)")
        }.value
    }
    
    // MARK: - Series Grouping & Logic
    
    private func fetchSeriesEcosystem(baseInfo: ContentInfo) async {
        guard let repo = repository else { return }
        let cleanTitle = baseInfo.normalizedTitle
        let targetSeriesId = self.channel.seriesId
        
        let allFiles: [Channel] = await Task.detached(priority: .userInitiated) {
            let ctx = repo.container.newBackgroundContext()
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            
            if let sid = targetSeriesId, sid != "0" {
                req.predicate = NSPredicate(format: "seriesId == %@", sid)
            } else {
                req.predicate = NSPredicate(
                    format: "type == 'series_episode' AND title BEGINSWITH[cd] %@",
                    String(cleanTitle.prefix(4))
                )
            }
            
            let candidates = (try? ctx.fetch(req)) ?? []
            return candidates.filter { ch in
                if let sid = targetSeriesId, sid != "0", ch.seriesId == sid { return true }
                let info = TitleNormalizer.parse(rawTitle: ch.canonicalTitle ?? ch.title)
                return TitleNormalizer.similarity(between: cleanTitle, and: info.normalizedTitle) > 0.85
            }
        }.value
        
        var registry: [String: [EpisodeVersion]] = [:]
        var foundSeasons = Set<Int>()
        
        for file in allFiles {
            let s = Int(file.season)
            let e = Int(file.episode)
            if s == 0 && e == 0 { continue }
            
            let key = String(format: "S%02dE%02d", s, e)
            foundSeasons.insert(s)
            
            let raw = file.canonicalTitle ?? file.title
            let info = TitleNormalizer.parse(rawTitle: raw)
            var score = info.qualityScore
            
            if let lang = info.language, lang.lowercased().contains(self.settings.preferredLanguage.lowercased()) {
                score += 10000
            }
            if file.seriesId != nil { score += 500 }
            
            let label = "\(info.language ?? "Default") \(info.quality)"
            let version = EpisodeVersion(channel: file, qualityLabel: label, score: score)
            
            registry[key, default: []].append(version)
        }
        
        for (key, _) in registry { registry[key]?.sort { $0.score > $1.score } }
        
        self.episodeRegistry = registry
        self.seasons = foundSeasons.sorted()
        
        if !self.seasons.contains(self.selectedSeason), let first = self.seasons.first {
            self.selectedSeason = first
        }
    }
    
    func selectSeason(_ season: Int) async {
        self.selectedSeason = season
        
        // Display what we have locally.
        // Since we are using OMDB for series now, we won't have TMDB-based episode metadata maps.
        // We will just show the file names or simple "Episode X" unless we want to fetch full season details from OMDB too.
        // To save API calls, we'll rely on the file title for now or just generic numbering.
        
        var displayList: [MergedEpisode] = []
        let seasonPrefix = String(format: "S%02d", season)
        let localKeys = episodeRegistry.keys.filter { $0.hasPrefix(seasonPrefix) }
        let sortedKeys = localKeys.sorted()
        
        for key in sortedKeys {
            guard let versions = episodeRegistry[key] else { continue }
            let epNum = Int(key.suffix(2)) ?? 0
            
            // Basic Construction
            let merged = MergedEpisode(
                id: key,
                season: season,
                number: epNum,
                title: "Episode \(epNum)", // Fallback since we aren't deep-fetching season details from OMDB yet to save calls
                overview: "",
                stillPath: nil,
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
            self.directPlayChannel = best.channel
        }
    }
    
    func triggerDirectPlay(_ episode: MergedEpisode) {
        if let best = episode.getBestVersion() {
            self.directPlayChannel = best.channel
        }
    }
    
    // MARK: - Version Selection
    
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
    
    // MARK: - Progress & History
    
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
