import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class DetailsViewModel: ObservableObject {
    
    // --- Data Sources ---
    @Published var channel: Channel
    @Published var tmdbDetails: TmdbDetails?
    @Published var omdbDetails: OmdbSeriesDetails?
    @Published var cast: [TmdbCast] = []
    
    // --- UI State ---
    @Published var isFavorite: Bool = false
    @Published var isLoading: Bool = true
    @Published var backgroundUrl: URL?
    @Published var posterUrl: URL?
    @Published var backdropOpacity: Double = 0.0
    
    // --- Series Management ---
    @Published var seasons: [Int] = []
    @Published var selectedSeason: Int = 1
    @Published var displayedEpisodes: [MergedEpisode] = []
    
    // --- Version & Playback Logic ---
    // Movie Versions (If this is a movie)
    @Published var movieVersions: [VersionOption] = []
    
    // Interaction State (Popups)
    @Published var showVersionPicker: Bool = false
    @Published var pickerTitle: String = ""
    @Published var pickerOptions: [VersionOption] = []
    @Published var onPickerSelect: ((Channel) -> Void)? = nil
    
    // Smart Play Button
    @Published var playButtonLabel: String = "Play"
    @Published var nextUpEpisode: MergedEpisode? = nil
    @Published var playButtonIcon: String = "play.fill"
    
    // --- Dependencies ---
    private let tmdbClient = TmdbClient()
    private let omdbClient = OmdbClient()
    private let xtreamClient = XtreamClient()
    private var repository: PrimeFlixRepository?
    
    // --- Internal Caches ---
    // Maps Season -> Episode Number -> List of Variant Channels
    private var seriesEcosystem: [Int: [Int: [Channel]]] = [:]
    private var tmdbSeasonCache: [Int: [TmdbEpisode]] = [:]
    
    // MARK: - Models
    
    struct MergedEpisode: Identifiable {
        let id: String // Unique ID (e.g., "S01E01")
        let season: Int
        let number: Int
        let title: String
        let overview: String
        let stillPath: URL?
        var versions: [VersionOption]
        var isWatched: Bool
        var progress: Double
        
        var displayTitle: String { "S\(season) E\(number) - \(title)" }
        
        // Helper to find the default version based on user prefs (highest score)
        var defaultVersion: VersionOption? {
            return versions.first // Assumes versions are already sorted by score
        }
    }
    
    struct VersionOption: Identifiable {
        let id: String // Channel URL
        let channel: Channel
        let quality: String
        let language: String
        let score: Int // Preference Score
        
        var label: String {
            return "\(quality) • \(language)"
        }
    }
    
    // MARK: - Init
    
    init(channel: Channel) {
        self.channel = channel
        self.isFavorite = channel.isFavorite
        if let cover = channel.cover {
            self.posterUrl = URL(string: cover)
            self.backgroundUrl = URL(string: cover)
        }
    }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
    }
    
    func loadData() async {
        self.isLoading = true
        
        // 1. Lazy Sync Episodes (Series Only) - Check if we need to fetch from Xtream API
        if channel.type == "series" && channel.seriesId != nil && channel.seriesId != "0" {
            await ingestXtreamEpisodes(seriesId: channel.seriesId!)
        }
        
        // 2. Fetch Ecosystem (Versions & Episodes)
        if channel.type == "series" || channel.type == "series_episode" {
            await loadSeriesData()
        } else {
            await loadMovieVersions()
        }
        
        // 3. Fetch Metadata (Parallel)
        // We fetch TMDB/OMDB data to enrich the UI (Cast, Plot, Ratings)
        await fetchMetadata()
        
        // 4. UI Finalization
        await recalculateSmartPlay()
        
        withAnimation { self.isLoading = false }
        withAnimation(.easeIn(duration: 0.5)) { self.backdropOpacity = 1.0 }
    }
    
    // MARK: - Logic: Movies
    
    private func loadMovieVersions() async {
        guard let repo = repository else { return }
        let service = VersioningService(context: repo.container.viewContext)
        
        // Use strict normalized grouping to find duplicates (4K, HD, etc.)
        let rawVersions = service.getVersions(for: channel)
        
        self.movieVersions = processVersions(rawVersions)
        
        // If we found a "better" version (e.g. 4K) than the one currently holding the metadata,
        // silently swap the underlying channel object so the "Play" button defaults correctly.
        if let best = self.movieVersions.first?.channel {
            self.channel = best
        }
    }
    
    func onPlayMovie() {
        if movieVersions.count > 1 {
            // Show Picker
            self.pickerTitle = "Select Version"
            self.pickerOptions = movieVersions
            self.onPickerSelect = { [weak self] selected in
                self?.triggerPlay(channel: selected)
            }
            self.showVersionPicker = true
        } else if let only = movieVersions.first {
            // Direct Play
            triggerPlay(channel: only.channel)
        } else {
            // Fallback
            triggerPlay(channel: channel)
        }
    }
    
    // MARK: - Logic: Series
    
    private func loadSeriesData() async {
        guard let repo = repository else { return }
        let service = VersioningService(context: repo.container.viewContext)
        
        // 1. Fetch ALL episodes/versions for this show
        let allFiles = service.getSeriesEcosystem(for: channel)
        
        // 2. Group into structured hierarchy: Season -> Episode -> [Variants]
        var hierarchy: [Int: [Int: [Channel]]] = [:]
        var foundSeasons = Set<Int>()
        
        for file in allFiles {
            let s = Int(file.season)
            let e = Int(file.episode)
            if s == 0 && e == 0 { continue } // Skip containers or bad data
            
            foundSeasons.insert(s)
            
            if hierarchy[s] == nil { hierarchy[s] = [:] }
            if hierarchy[s]![e] == nil { hierarchy[s]![e] = [] }
            
            hierarchy[s]![e]?.append(file)
        }
        
        self.seriesEcosystem = hierarchy
        self.seasons = foundSeasons.sorted()
        
        // Select initial season (Logic: First season, or current if already set)
        if !seasons.contains(selectedSeason), let first = seasons.first {
            self.selectedSeason = first
        }
        
        await loadSeasonContent(selectedSeason)
    }
    
    func loadSeasonContent(_ season: Int) async {
        self.selectedSeason = season
        guard let epMap = seriesEcosystem[season] else { return }
        
        // Fetch TMDB Season Data for Titles/Stills if not cached
        var tmdbData: [TmdbEpisode] = []
        if let tmdbId = tmdbDetails?.id {
            if let cached = tmdbSeasonCache[season] {
                tmdbData = cached
            } else if let fetched = try? await tmdbClient.getTvSeason(tvId: tmdbId, seasonNumber: season) {
                tmdbData = fetched.episodes
                tmdbSeasonCache[season] = tmdbData
            }
        }
        
        var list: [MergedEpisode] = []
        
        for epNum in epMap.keys.sorted() {
            guard let variants = epMap[epNum] else { continue }
            
            // Rank the versions (4K English > HD French, etc.)
            let processedVersions = processVersions(variants)
            
            // Metadata Mapping
            let meta = tmdbData.first(where: { $0.episodeNumber == epNum })
            let still: URL? = meta?.stillPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
            
            // Check Progress (Any version watched?)
            // We check the repo asynchronously for progress on ALL variant URLs
            let (isWatched, progress) = await getCompositeProgress(for: variants)
            
            let merged = MergedEpisode(
                id: "S\(season)E\(epNum)",
                season: season,
                number: epNum,
                title: meta?.name ?? "Episode \(epNum)",
                overview: meta?.overview ?? "",
                stillPath: still,
                versions: processedVersions,
                isWatched: isWatched,
                progress: progress
            )
            list.append(merged)
        }
        
        withAnimation {
            self.displayedEpisodes = list
        }
    }
    
    func onPlayEpisode(_ episode: MergedEpisode) {
        if episode.versions.count > 1 {
            self.pickerTitle = episode.displayTitle
            self.pickerOptions = episode.versions
            self.onPickerSelect = { [weak self] selected in
                self?.triggerPlay(channel: selected)
            }
            self.showVersionPicker = true
        } else if let only = episode.versions.first {
            triggerPlay(channel: only.channel)
        }
    }
    
    // MARK: - Helper: Version Processing & Sorting
    
    /// Converts raw Channels into sorted `VersionOption`s based on user preferences.
    private func processVersions(_ channels: [Channel]) -> [VersionOption] {
        let preferredLang = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "English"
        let preferredRes = UserDefaults.standard.string(forKey: "preferredResolution") ?? "4K"
        
        return channels.map { ch in
            // Parse the raw title (e.g. "Movie.Title.2024.FRENCH.1080p")
            // Note: We use canonicalTitle if available as it retains the tags stripped from 'title'
            let raw = ch.canonicalTitle ?? ch.title
            let info = TitleNormalizer.parse(rawTitle: raw)
            
            var score = info.qualityScore
            
            // Boost Score for Language Match
            let lang = info.language ?? "Unknown"
            if lang.localizedCaseInsensitiveContains(preferredLang) {
                score += 10000
            }
            
            // Boost Score for Resolution Match
            let qual = info.quality
            if qual.localizedCaseInsensitiveContains(preferredRes) {
                score += 5000
            }
            
            return VersionOption(
                id: ch.url,
                channel: ch,
                quality: info.quality,
                language: lang,
                score: score
            )
        }.sorted { $0.score > $1.score } // Highest score first (Default selection)
    }
    
    private func getCompositeProgress(for channels: [Channel]) async -> (Bool, Double) {
        guard let repo = repository else { return (false, 0) }
        let urls = channels.map { $0.url }
        
        return await Task.detached {
            let ctx = repo.container.newBackgroundContext()
            let req = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            req.predicate = NSPredicate(format: "channelUrl IN %@", urls)
            
            var maxProg = 0.0
            if let results = try? ctx.fetch(req) {
                for p in results {
                    if p.duration > 0 {
                        let pct = Double(p.position) / Double(p.duration)
                        if pct > maxProg { maxProg = pct }
                    }
                }
            }
            return (maxProg > 0.9, maxProg)
        }.value
    }
    
    // MARK: - Smart Play Calculation
    
    private func recalculateSmartPlay() async {
        if channel.type == "series" || channel.type == "series_episode" {
            // Find first unwatched episode in current season list
            // (Note: For a production app, we should check across ALL seasons, but checking displayed list is fast)
            if let next = displayedEpisodes.first(where: { !$0.isWatched }) {
                self.nextUpEpisode = next
                self.playButtonLabel = "Continue S\(next.season) E\(next.number)"
                self.playButtonIcon = "play.fill"
            } else {
                // If all watched, or just starting
                if let first = displayedEpisodes.first {
                    self.nextUpEpisode = first
                    self.playButtonLabel = "Start Series"
                    self.playButtonIcon = "play.fill"
                }
            }
        } else {
            // Movie logic
            // Check if we have progress on the BEST version
            if let bestVersion = movieVersions.first {
                let (_, prog) = await getCompositeProgress(for: [bestVersion.channel])
                if prog > 0.05 && prog < 0.9 {
                    self.playButtonLabel = "Resume"
                    self.playButtonIcon = "play.fill"
                } else {
                    self.playButtonLabel = "Play"
                    self.playButtonIcon = "play.fill"
                }
            }
        }
    }
    
    // MARK: - Metadata Fetching
    
    private func fetchMetadata() async {
        let info = TitleNormalizer.parse(rawTitle: channel.canonicalTitle ?? channel.title)
        
        async let tmdb = tmdbClient.findBestMatch(title: info.normalizedTitle, year: info.year, type: channel.type == "series" ? "series" : "movie")
        async let omdb = omdbClient.getSeriesMetadata(title: info.normalizedTitle, year: info.year)
        
        let (tmdbMatch, omdbData) = await (tmdb, omdb)
        
        if let match = tmdbMatch {
            if channel.type == "series" {
                if let details = try? await tmdbClient.getTvDetails(id: match.id) {
                    self.tmdbDetails = details
                    if let cast = details.aggregateCredits?.cast { self.cast = cast }
                    if let bg = details.backdropPath { self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(bg)") }
                }
            } else {
                if let details = try? await tmdbClient.getMovieDetails(id: match.id) {
                    self.tmdbDetails = details
                    if let cast = details.credits?.cast { self.cast = cast }
                    if let bg = details.backdropPath { self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(bg)") }
                }
            }
        }
        
        if let omdb = omdbData {
            self.omdbDetails = omdb
        }
    }
    
    // MARK: - Lazy Sync (Episodes)
    
    private func ingestXtreamEpisodes(seriesId: String) async {
        guard let repo = repository else { return }
        
        // 1. Check if episodes already exist
        let hasEpisodes: Bool = await Task.detached {
            let ctx = repo.container.newBackgroundContext()
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            req.predicate = NSPredicate(format: "seriesId == %@ AND type == 'series_episode'", seriesId)
            req.fetchLimit = 1
            return (try? ctx.count(for: req)) ?? 0 > 0
        }.value
        
        if hasEpisodes { return }
        
        // 2. Fetch from Network if missing
        let input = XtreamInput.decodeFromPlaylistUrl(channel.playlistUrl)
        
        guard let episodes = try? await xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesId) else {
            print("❌ Failed to lazy-load episodes for Series \(seriesId)")
            return
        }
        
        let showCover = self.channel.cover
        
        await Task.detached {
            let ctx = repo.container.newBackgroundContext()
            ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            let objects = episodes.map { ep -> [String: Any] in
                // We use ChannelStruct factory to parse standard Xtream response into our model
                // Note: We use an empty category map as we are inside a series detail view
                let structItem = ChannelStruct.from(ep, seriesId: seriesId, playlistUrl: input.basicUrl, input: input, cover: showCover)
                return structItem.toDictionary()
            }
            
            let batchInsert = NSBatchInsertRequest(entity: Channel.entity(), objects: objects)
            _ = try? ctx.execute(batchInsert)
            try? ctx.save()
            print("✅ Lazy-loaded \(objects.count) episodes for Series \(seriesId)")
        }.value
    }
    
    // MARK: - Actions
    
    func toggleFavorite() {
        repository?.toggleFavorite(channel)
        self.isFavorite.toggle()
    }
    
    private func triggerPlay(channel: Channel) {
        // Notification bubbles up to ContentView to trigger the Player
        NotificationCenter.default.post(name: NSNotification.Name("PlayChannel"), object: channel)
    }
    
    // Helper used by the main Play button
    func onPlaySmartTarget() {
        if let next = nextUpEpisode {
            onPlayEpisode(next)
        } else {
            onPlayMovie()
        }
    }
}
