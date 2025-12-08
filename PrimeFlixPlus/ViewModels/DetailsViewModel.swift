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
            // CRITICAL FIX: Ingest episodes for THIS series AND any duplicate entries (e.g. English + French containers)
            await ingestAllMatchingSeries()
            await loadSeriesData()
        } else {
            await loadMovieVersions()
        }
        
        await fetchMetadata()
        await recalculateSmartPlay()
        
        withAnimation { self.isLoading = false }
        withAnimation(.easeIn(duration: 0.5)) { self.backdropOpacity = 1.0 }
    }
    
    // MARK: - Series Ingestion (The Fix)
    
    private func ingestAllMatchingSeries() async {
        guard let repo = repository else { return }
        
        // FIX: Capture the objectID on the MainActor BEFORE the detached task
        // Accessing 'self.channel' inside Task.detached is unsafe without await
        let targetObjectID = self.channel.objectID
        
        // 1. Find all Series Containers that match this title (e.g. ID 1234 "Stranger Things" and ID 5678 "Stranger Things (FR)")
        // We run this on background context
        let matchingContainers: [Channel] = await Task.detached {
            let ctx = repo.container.newBackgroundContext()
            let service = VersioningService(context: ctx)
            // Re-fetch the current channel in this context using the captured ID
            guard let contextChannel = try? ctx.existingObject(with: targetObjectID) as? Channel else { return [] }
            return service.findMatchingSeriesContainers(title: contextChannel.title)
        }.value
        
        // 2. Identify which IDs need syncing
        // (If we already have episodes for ID 5678, don't re-fetch)
        var idsToSync: [String] = []
        let ctx = repo.container.viewContext
        
        for container in matchingContainers {
            guard let sid = container.seriesId, sid != "0" else { continue }
            
            // Check if episodes exist for this specific ID
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            req.predicate = NSPredicate(format: "seriesId == %@ AND type == 'series_episode'", sid)
            req.fetchLimit = 1
            let count = (try? ctx.count(for: req)) ?? 0
            
            if count == 0 {
                idsToSync.append(sid)
            }
        }
        
        // 3. Parallel Ingest
        // Fetch episodes for the English ID, French ID, etc. concurrently
        if !idsToSync.isEmpty {
            print("🔄 Smart Sync: Fetching episodes for Series IDs: \(idsToSync)")
            await withTaskGroup(of: Void.self) { group in
                for sid in idsToSync {
                    // Find the container for this ID to get playlist URL
                    if let container = matchingContainers.first(where: { $0.seriesId == sid }) {
                        group.addTask {
                            await self.ingestXtreamEpisodes(for: container, seriesId: sid)
                        }
                    }
                }
            }
        }
    }
    
    private func ingestXtreamEpisodes(for container: Channel, seriesId: String) async {
        let input = XtreamInput.decodeFromPlaylistUrl(container.playlistUrl)
        
        guard let episodes = try? await xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesId) else {
            print("❌ Failed to load episodes for Series \(seriesId)")
            return
        }
        
        guard let repo = repository else { return }
        let showCover = container.cover
        let playlistUrl = container.playlistUrl
        
        await Task.detached {
            let ctx = repo.container.newBackgroundContext()
            ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            let objects = episodes.map { ep -> [String: Any] in
                let structItem = ChannelStruct.from(ep, seriesId: seriesId, playlistUrl: playlistUrl, input: input, cover: showCover)
                return structItem.toDictionary()
            }
            
            let batchInsert = NSBatchInsertRequest(entity: Channel.entity(), objects: objects)
            _ = try? ctx.execute(batchInsert)
            try? ctx.save()
            print("✅ Ingested \(objects.count) episodes for Series ID \(seriesId)")
        }.value
    }
    
    // MARK: - Logic: Series Display
    
    private func loadSeriesData() async {
        guard let repo = repository else { return }
        let service = VersioningService(context: repo.container.viewContext)
        
        let allFiles = service.getSeriesEcosystem(for: channel)
        
        // Group by Season -> Episode
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
            let processedVersions = processVersions(variants)
            
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
    
    // MARK: - Interactions
    
    func onPlayEpisode(_ episode: MergedEpisode) {
        // THIS LOGIC HANDLES THE POPUP
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
    
    // MARK: - Logic: Movies
    
    private func loadMovieVersions() async {
        guard let repo = repository else { return }
        let service = VersioningService(context: repo.container.viewContext)
        let rawVersions = service.getVersions(for: channel)
        
        self.movieVersions = processVersions(rawVersions)
        
        if let best = self.movieVersions.first?.channel {
            self.channel = best
        }
    }
    
    func onPlayMovie() {
        if movieVersions.count > 1 {
            self.pickerTitle = "Select Version"
            self.pickerOptions = movieVersions
            self.onPickerSelect = { [weak self] selected in
                self?.triggerPlay(channel: selected)
            }
            self.showVersionPicker = true
        } else if let only = movieVersions.first {
            triggerPlay(channel: only.channel)
        } else {
            triggerPlay(channel: channel)
        }
    }
    
    // MARK: - Helpers
    
    private func processVersions(_ channels: [Channel]) -> [VersionOption] {
        let preferredLang = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "English"
        let preferredRes = UserDefaults.standard.string(forKey: "preferredResolution") ?? "4K"
        
        return channels.map { ch in
            let raw = ch.canonicalTitle ?? ch.title
            let info = TitleNormalizer.parse(rawTitle: raw)
            
            var score = info.qualityScore
            let lang = info.language ?? "Unknown"
            if lang.localizedCaseInsensitiveContains(preferredLang) { score += 10000 }
            let qual = info.quality
            if qual.localizedCaseInsensitiveContains(preferredRes) { score += 5000 }
            
            return VersionOption(
                id: ch.url,
                channel: ch,
                quality: qual,
                language: lang,
                score: score
            )
        }.sorted { $0.score > $1.score }
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
        
        if let omdb = omdbData {
            self.omdbDetails = omdb
        }
    }
    
    func toggleFavorite() {
        repository?.toggleFavorite(channel)
        self.isFavorite.toggle()
    }
    
    private func triggerPlay(channel: Channel) {
        NotificationCenter.default.post(name: NSNotification.Name("PlayChannel"), object: channel)
    }
    
    func onPlaySmartTarget() {
        if let next = nextUpEpisode {
            onPlayEpisode(next)
        } else {
            onPlayMovie()
        }
    }
}
