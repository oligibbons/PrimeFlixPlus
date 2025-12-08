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
    
    // --- Versioning & Playback ---
    @Published var movieVersions: [VersionOption] = []
    @Published var showVersionPicker: Bool = false
    @Published var pickerTitle: String = ""
    @Published var pickerOptions: [VersionOption] = []
    @Published var onPickerSelect: ((Channel) -> Void)? = nil
    
    @Published var playButtonLabel: String = "Play"
    @Published var nextUpEpisode: MergedEpisode? = nil
    @Published var playButtonIcon: String = "play.fill"
    
    // --- Dependencies ---
    private let tmdbClient = TmdbClient()
    private let omdbClient = OmdbClient()
    private let xtreamClient = XtreamClient()
    private var repository: PrimeFlixRepository?
    private let settings = SettingsViewModel()
    
    // --- Internal ---
    private var seriesEcosystem: [Int: [Int: [Channel]]] = [:]
    private var tmdbSeasonCache: [Int: [TmdbEpisode]] = [:]
    
    // MAP: SeriesID -> Metadata (Language/Quality) derived from the Container Title
    // e.g. ["12345": ContentInfo(language: "English", quality: "4K")]
    private var seriesMetadataMap: [String: ContentInfo] = [:]
    
    // MARK: - Models
    
    struct MergedEpisode: Identifiable {
        let id: String
        let season: Int
        let number: Int
        let title: String
        let overview: String
        let stillPath: URL?
        var versions: [VersionOption]
        var isWatched: Bool
        var progress: Double
        
        var displayTitle: String { "S\(season) E\(number) - \(title)" }
    }
    
    struct VersionOption: Identifiable {
        let id: String
        let channel: Channel
        let quality: String
        let language: String
        let score: Int
        
        var label: String { "\(quality) • \(language)" }
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
    
    // MARK: - Main Load Logic
    
    func loadData() async {
        self.isLoading = true
        
        if channel.type == "series" || channel.type == "series_episode" {
            // 1. Find and Ingest duplicates (English, French, etc.)
            let seriesIds = await ingestAllMatchingSeries()
            // 2. Load episodes for ALL those IDs
            await loadSeriesData(seriesIds: seriesIds)
        } else {
            await loadMovieVersions()
        }
        
        await fetchMetadata()
        await recalculateSmartPlay()
        
        withAnimation { self.isLoading = false }
        withAnimation(.easeIn(duration: 0.5)) { self.backdropOpacity = 1.0 }
    }
    
    // MARK: - Series Ingestion & ID Mapping
    
    private func ingestAllMatchingSeries() async -> [String] {
        guard let repo = repository else { return [] }
        
        // FIX: Capture values on MainActor before passing to background Task
        let targetObjectID = self.channel.objectID
        let container = repo.container
        
        // A. Find all Series Containers matching this title
        let task = Task.detached { () -> [Channel] in
            let ctx = container.newBackgroundContext()
            let service = VersioningService(context: ctx)
            // Re-fetch safe object on background context
            guard let contextChannel = try? ctx.existingObject(with: targetObjectID) as? Channel else { return [] }
            return service.findMatchingSeriesContainers(title: contextChannel.title)
        }
        
        let matchingContainers = await task.value
        
        var allIds: [String] = []
        
        // B. Populate Metadata Map & Identify Missing Content
        var idsToSync: [String] = []
        let ctx = repo.container.viewContext
        
        for container in matchingContainers {
            guard let sid = container.seriesId, sid != "0" else { continue }
            allIds.append(sid)
            
            // Extract Metadata from Container Title (e.g. "Stranger Things (EN) 4K")
            let rawTitle = container.canonicalTitle ?? container.title
            self.seriesMetadataMap[sid] = TitleNormalizer.parse(rawTitle: rawTitle)
            
            // Check if episodes exist
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            req.predicate = NSPredicate(format: "seriesId == %@ AND type == 'series_episode'", sid)
            req.fetchLimit = 1
            if (try? ctx.count(for: req)) ?? 0 == 0 {
                idsToSync.append(sid)
            }
        }
        
        // C. Parallel Ingest for missing IDs
        if !idsToSync.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for sid in idsToSync {
                    if let container = matchingContainers.first(where: { $0.seriesId == sid }) {
                        group.addTask {
                            await self.ingestXtreamEpisodes(for: container, seriesId: sid)
                        }
                    }
                }
            }
        }
        
        return allIds
    }
    
    private func ingestXtreamEpisodes(for container: Channel, seriesId: String) async {
        let input = XtreamInput.decodeFromPlaylistUrl(container.playlistUrl)
        guard let episodes = try? await xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesId) else { return }
        
        guard let repo = repository else { return }
        
        // Capture simple values for the background task
        let showCover = container.cover
        let playlistUrl = container.playlistUrl
        let containerRef = repo.container
        
        await Task.detached {
            let ctx = containerRef.newBackgroundContext()
            ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            let objects = episodes.map { ep -> [String: Any] in
                let structItem = ChannelStruct.from(ep, seriesId: seriesId, playlistUrl: playlistUrl, input: input, cover: showCover)
                return structItem.toDictionary()
            }
            
            let batchInsert = NSBatchInsertRequest(entity: Channel.entity(), objects: objects)
            _ = try? ctx.execute(batchInsert)
            try? ctx.save()
        }.value
    }
    
    // MARK: - Logic: Series Display
    
    private func loadSeriesData(seriesIds: [String]) async {
        guard let repo = repository else { return }
        let container = repo.container
        
        // 1. Fetch episodes for ALL Series IDs
        let allFiles = await Task.detached { () -> [Channel] in
            let ctx = container.newBackgroundContext()
            let service = VersioningService(context: ctx)
            return service.getEpisodes(for: seriesIds)
        }.value
        
        // 2. Group by Season -> Episode
        var hierarchy: [Int: [Int: [Channel]]] = [:]
        var foundSeasons = Set<Int>()
        
        for file in allFiles {
            let s = Int(file.season)
            let e = Int(file.episode)
            if s == 0 && e == 0 { continue }
            
            foundSeasons.insert(s)
            if hierarchy[s] == nil { hierarchy[s] = [:] }
            if hierarchy[s]![e] == nil { hierarchy[s]![e] = [] }
            
            hierarchy[s]![e]?.append(file)
        }
        
        self.seriesEcosystem = hierarchy
        self.seasons = foundSeasons.sorted()
        
        if !seasons.contains(selectedSeason), let first = seasons.first {
            self.selectedSeason = first
        }
        
        await loadSeasonContent(selectedSeason)
    }
    
    func loadSeasonContent(_ season: Int) async {
        self.selectedSeason = season
        guard let epMap = seriesEcosystem[season] else { return }
        
        // TMDB Metadata
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
            let processedVersions = processVersions(variants) // INHERITS METADATA HERE
            
            let meta = tmdbData.first(where: { $0.episodeNumber == epNum })
            let still: URL? = meta?.stillPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
            
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
        
        withAnimation { self.displayedEpisodes = list }
    }
    
    // MARK: - Interactions & Helpers
    
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
    
    private func processVersions(_ channels: [Channel]) -> [VersionOption] {
        let preferredLang = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "English"
        let preferredRes = UserDefaults.standard.string(forKey: "preferredResolution") ?? "4K"
        
        return channels.map { ch in
            // STRATEGY: Prefer Metadata from the Parent Series Container if available
            // If the episode title is generic ("Episode 1"), looking at the Series Container ("Stranger Things [FR]") gives us the language.
            var quality = ch.quality ?? "HD"
            var language = "Unknown"
            
            // 1. Try deriving from Series ID Map
            if let sid = ch.seriesId, let parentInfo = self.seriesMetadataMap[sid] {
                if let pLang = parentInfo.language { language = pLang }
                if !parentInfo.quality.isEmpty { quality = parentInfo.quality }
            }
            
            // 2. Fallback: Parse the episode title itself
            let epInfo = TitleNormalizer.parse(rawTitle: ch.canonicalTitle ?? ch.title)
            if language == "Unknown", let eLang = epInfo.language { language = eLang }
            if quality == "HD" && !epInfo.quality.isEmpty { quality = epInfo.quality }
            
            // Scoring
            var score = 0
            if quality.contains("4K") { score += 4000 } else if quality.contains("1080") { score += 1080 }
            if language.localizedCaseInsensitiveContains(preferredLang) { score += 10000 }
            if quality.localizedCaseInsensitiveContains(preferredRes) { score += 5000 }
            
            return VersionOption(
                id: ch.url,
                channel: ch,
                quality: quality,
                language: language,
                score: score
            )
        }.sorted { $0.score > $1.score }
    }
    
    private func loadMovieVersions() async {
        guard let repo = repository else { return }
        
        // Use MainActor context for simple movie version lookup
        let service = VersioningService(context: repo.container.viewContext)
        let rawVersions = service.getVersions(for: channel)
        self.movieVersions = processVersions(rawVersions)
        if let best = self.movieVersions.first?.channel { self.channel = best }
    }
    
    func onPlayMovie() {
        if movieVersions.count > 1 {
            self.pickerTitle = "Select Version"
            self.pickerOptions = movieVersions
            self.onPickerSelect = { [weak self] selected in self?.triggerPlay(channel: selected) }
            self.showVersionPicker = true
        } else if let only = movieVersions.first {
            triggerPlay(channel: only.channel)
        } else {
            triggerPlay(channel: channel)
        }
    }
    
    private func getCompositeProgress(for channels: [Channel]) async -> (Bool, Double) {
        guard let repo = repository else { return (false, 0) }
        let urls = channels.map { $0.url }
        let container = repo.container
        
        return await Task.detached {
            let ctx = container.newBackgroundContext()
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
    
    private func recalculateSmartPlay() async {
        if channel.type == "series" || channel.type == "series_episode" {
            if let next = displayedEpisodes.first(where: { !$0.isWatched }) {
                self.nextUpEpisode = next
                self.playButtonLabel = "Continue S\(next.season) E\(next.number)"
            } else {
                self.nextUpEpisode = displayedEpisodes.first
                self.playButtonLabel = "Start Series"
            }
        } else {
            self.playButtonLabel = "Play Movie"
        }
    }
    
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
        if let omdb = omdbData { self.omdbDetails = omdb }
    }
    
    func toggleFavorite() { repository?.toggleFavorite(channel); self.isFavorite.toggle() }
    private func triggerPlay(channel: Channel) { NotificationCenter.default.post(name: NSNotification.Name("PlayChannel"), object: channel) }
    func onPlaySmartTarget() { if let next = nextUpEpisode { onPlayEpisode(next) } else { onPlayMovie() } }
}
