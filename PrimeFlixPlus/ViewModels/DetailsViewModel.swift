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
    @Published var isInWatchlist: Bool = false
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
    
    // Pass ChannelStruct to allow safe handling from Views
    @Published var onPickerSelect: ((ChannelStruct) -> Void)? = nil
    
    @Published var playButtonLabel: String = "Play"
    @Published var nextUpEpisode: MergedEpisode? = nil
    @Published var playButtonIcon: String = "play.fill"
    
    // --- Dependencies ---
    private let tmdbClient = TmdbClient()
    private let omdbClient = OmdbClient()
    private let xtreamClient = XtreamClient()
    private var repository: PrimeFlixRepository?
    private var nextEpisodeService: NextEpisodeService?
    
    // --- Internal ---
    private var seriesEcosystem: [Int: [Int: [ChannelStruct]]] = [:]
    private var tmdbSeasonCache: [Int: [TmdbEpisode]] = [:]
    private var omdbSeasonCache: [Int: [OmdbEpisodeDetails]] = [:]
    
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
        let channelStruct: ChannelStruct
        let quality: String
        let language: String
        let score: Int
        
        var label: String { "\(quality) • \(language)" }
    }
    
    // MARK: - Init
    
    init(channel: Channel) {
        self.channel = channel
        self.isFavorite = channel.isFavorite
        self.isInWatchlist = channel.inWatchlist
        if let cover = channel.cover {
            self.posterUrl = URL(string: cover)
            self.backgroundUrl = URL(string: cover)
        }
    }
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.nextEpisodeService = NextEpisodeService(context: repository.container.viewContext)
    }
    
    // MARK: - Main Load Logic
    
    func loadData() async {
        self.isLoading = true
        
        let targetObjectID = self.channel.objectID
        let isSeriesType = (channel.type == "series" || channel.type == "series_episode")
        
        guard let repo = repository else { return }
        let container = repo.container
        
        // 1. Heavy Lifting on Background Thread
        let result = await Task.detached { () -> (episodes: [ChannelStruct], versions: [ChannelStruct], metaMap: [String: ContentInfo]) in
            let ctx = container.newBackgroundContext()
            ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            let service = VersioningService(context: ctx)
            
            guard let bgChannel = try? ctx.existingObject(with: targetObjectID) as? Channel else {
                return ([], [], [:])
            }
            
            if isSeriesType {
                // A. Find Series Containers
                let containers = service.findMatchingSeriesContainers(title: bgChannel.title)
                
                // B. Build Metadata Map
                var metaMap: [String: ContentInfo] = [:]
                var idsToSync: [ChannelStruct] = []
                var allSeriesIds: [String] = []
                
                for container in containers {
                    guard let sid = container.seriesId, sid != "0" else { continue }
                    allSeriesIds.append(sid)
                    
                    let rawTitle = container.canonicalTitle ?? container.title
                    let info = TitleNormalizer.parse(rawTitle: rawTitle)
                    metaMap[sid] = info
                    
                    let countReq = NSFetchRequest<Channel>(entityName: "Channel")
                    countReq.predicate = NSPredicate(format: "seriesId == %@ AND type == 'series_episode'", sid)
                    if (try? ctx.count(for: countReq)) ?? 0 == 0 {
                        idsToSync.append(ChannelStruct(entity: container))
                    }
                }
                
                // C. Ingest Missing Episodes
                if !idsToSync.isEmpty {
                    await DetailsViewModel.ingestMissingEpisodes(containers: idsToSync, client: XtreamClient(), context: ctx)
                }
                
                // D. Fetch All Episodes
                let allEpisodes = service.getEpisodes(for: allSeriesIds)
                return (allEpisodes.map { ChannelStruct(entity: $0) }, [], metaMap)
                
            } else {
                // Movie Logic
                let versions = service.getVersions(for: bgChannel)
                return ([], versions.map { ChannelStruct(entity: $0) }, [:])
            }
        }.value
        
        // 2. Process Results
        self.seriesMetadataMap = result.metaMap
        
        await fetchMetadata()
        
        if isSeriesType {
            await processSeriesData(episodes: result.episodes)
        } else {
            processMovieVersions(structs: result.versions)
        }
        
        withAnimation { self.isLoading = false }
        withAnimation(.easeIn(duration: 0.5)) { self.backdropOpacity = 1.0 }
    }
    
    // MARK: - Ingestion Logic
    
    private static func ingestMissingEpisodes(containers: [ChannelStruct], client: XtreamClient, context: NSManagedObjectContext) async {
        await withTaskGroup(of: Void.self) { group in
            for container in containers {
                group.addTask {
                    guard let sid = container.seriesId else { return }
                    let input = XtreamInput.decodeFromPlaylistUrl(container.playlistUrl)
                    
                    if let episodes = try? await client.getSeriesEpisodes(input: input, seriesId: sid) {
                        await context.perform {
                            let objects = episodes.map { ep -> [String: Any] in
                                let structItem = ChannelStruct.from(ep, seriesId: sid, playlistUrl: container.playlistUrl, input: input, cover: container.cover)
                                return structItem.toDictionary()
                            }
                            let batchInsert = NSBatchInsertRequest(entity: Channel.entity(), objects: objects)
                            _ = try? context.execute(batchInsert)
                        }
                    }
                }
            }
        }
        try? context.performAndWait { try context.save() }
    }
    
    // MARK: - Series Processing & Resume Logic
    
    private func processSeriesData(episodes: [ChannelStruct]) async {
        var hierarchy: [Int: [Int: [ChannelStruct]]] = [:]
        var foundSeasons = Set<Int>()
        
        for ep in episodes {
            let s = ep.season
            let e = ep.episode
            if s == 0 && e == 0 { continue }
            foundSeasons.insert(s)
            hierarchy[s, default: [:]][e, default: []].append(ep)
        }
        
        self.seriesEcosystem = hierarchy
        self.seasons = foundSeasons.sorted()
        
        // Smart Resume: Determine which season/episode to show
        if let resumeState = await determineInitialState(episodes: episodes) {
            self.selectedSeason = resumeState.season
            self.nextUpEpisode = resumeState.targetEpisode
            
            // Format button
            self.playButtonIcon = (resumeState.isResume) ? "play.circle.fill" : "forward.end.fill"
            self.playButtonLabel = (resumeState.isResume)
                ? "Resume S\(resumeState.season) E\(resumeState.targetEpisode.number)"
                : "Play S\(resumeState.season) E\(resumeState.targetEpisode.number)"
            
        } else {
            // Default: First Season
            if !seasons.contains(selectedSeason), let first = seasons.first {
                self.selectedSeason = first
            }
            self.playButtonLabel = "Start Series"
            self.playButtonIcon = "play.fill"
        }
        
        await loadSeasonContent(selectedSeason)
    }
    
    /// Logic: Find last watched -> if < 95% resume, if > 95% find next.
    private func determineInitialState(episodes: [ChannelStruct]) async -> (season: Int, targetEpisode: MergedEpisode, isResume: Bool)? {
        guard let repo = repository else { return nil }
        
        // 1. Get Watch History for this show
        let urls = Set(episodes.map { $0.url })
        let ctx = repo.container.viewContext
        let req = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        req.predicate = NSPredicate(format: "channelUrl IN %@", urls)
        req.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
        req.fetchLimit = 1
        
        guard let lastWatch = try? ctx.fetch(req).first,
              let lastEpStruct = episodes.first(where: { $0.url == lastWatch.channelUrl }) else {
            return nil
        }
        
        // Calculate progress
        let pct = (lastWatch.duration > 0) ? Double(lastWatch.position) / Double(lastWatch.duration) : 0
        
        if pct < 0.95 {
            // CASE A: Resume current episode
            let merged = createMergedEpisode(from: lastEpStruct, progress: pct, isWatched: false)
            return (lastEpStruct.season, merged, true)
        } else {
            // CASE B: Find next episode
            // We temporarily map the struct to a managed object ID if needed, but since we have the struct:
            // Find S/E
            let currentS = lastEpStruct.season
            let currentE = lastEpStruct.episode
            
            // Look for S, E+1
            if let nextEpStruct = findEpisodeStruct(season: currentS, episode: currentE + 1) {
                let merged = createMergedEpisode(from: nextEpStruct, progress: 0, isWatched: false)
                return (currentS, merged, false)
            }
            // Look for S+1, E1
            if let nextSeasonFirst = findEpisodeStruct(season: currentS + 1, episode: 1) {
                let merged = createMergedEpisode(from: nextSeasonFirst, progress: 0, isWatched: false)
                return (currentS + 1, merged, false)
            }
        }
        
        return nil
    }
    
    private func findEpisodeStruct(season: Int, episode: Int) -> ChannelStruct? {
        // Just grab the first version of the target episode we find in the ecosystem
        return seriesEcosystem[season]?[episode]?.first
    }
    
    private func createMergedEpisode(from structItem: ChannelStruct, progress: Double, isWatched: Bool) -> MergedEpisode {
        // Quick helper for the Smart Resume logic (minimal metadata)
        return MergedEpisode(
            id: "S\(structItem.season)E\(structItem.episode)",
            season: structItem.season,
            number: structItem.episode,
            title: structItem.title, // Will be enriched later
            overview: "",
            stillPath: nil,
            versions: processVersions([structItem]),
            isWatched: isWatched,
            progress: progress
        )
    }
    
    // MARK: - Season Content Loader
    
    func loadSeasonContent(_ season: Int) async {
        self.selectedSeason = season
        guard let epMap = seriesEcosystem[season] else { return }
        
        // 1. Fetch Metadata (Priority: Cache -> OMDB -> TMDB)
        var omdbData: [OmdbEpisodeDetails] = []
        var tmdbData: [TmdbEpisode] = []
        
        if let oCached = omdbSeasonCache[season] {
            omdbData = oCached
        } else if let tCached = tmdbSeasonCache[season] {
            tmdbData = tCached
        } else {
            var omdbSuccess = false
            if let imdbID = omdbDetails?.imdbID {
                if let fetched = await omdbClient.getSeasonDetails(imdbID: imdbID, season: season) {
                    omdbData = fetched
                    omdbSeasonCache[season] = omdbData
                    omdbSuccess = true
                }
            }
            if !omdbSuccess, let tmdbId = tmdbDetails?.id {
                if let fetched = try? await tmdbClient.getTvSeason(tvId: tmdbId, seasonNumber: season) {
                    tmdbData = fetched.episodes
                    tmdbSeasonCache[season] = tmdbData
                }
            }
        }
        
        // 2. Build Merged List
        var list: [MergedEpisode] = []
        let sortedKeys = epMap.keys.sorted()
        
        for epNum in sortedKeys {
            guard let variants = epMap[epNum] else { continue }
            let processedVersions = processVersions(variants)
            if processedVersions.isEmpty { continue }
            
            // Metadata Resolution
            var title = "Episode \(epNum)"
            var overview = ""
            var still: URL? = nil
            
            if let meta = omdbData.first(where: { Int($0.episode ?? "0") == epNum }) {
                title = meta.title
                overview = meta.plot ?? ""
                if let poster = meta.poster, poster != "N/A" { still = URL(string: poster) }
            } else if let meta = tmdbData.first(where: { $0.episodeNumber == epNum }) {
                title = meta.name
                overview = meta.overview ?? ""
                if let path = meta.stillPath {
                    still = URL(string: "https://image.tmdb.org/t/p/w500\(path)")
                }
            }
            
            let localData = variants.first(where: { $0.cover != nil })
            if title.hasPrefix("Episode"), let localTitle = localData?.title {
                if !localTitle.lowercased().contains("episode") { title = localTitle }
            }
            
            if still == nil {
                if let localCover = localData?.cover { still = URL(string: localCover) }
                else if let fallbackCover = self.posterUrl { still = fallbackCover }
            }
            
            let (isWatched, progress) = await getCompositeProgress(for: variants)
            
            let merged = MergedEpisode(
                id: "S\(season)E\(epNum)",
                season: season,
                number: epNum,
                title: title,
                overview: overview,
                stillPath: still,
                versions: processedVersions,
                isWatched: isWatched,
                progress: progress
            )
            list.append(merged)
        }
        
        withAnimation { self.displayedEpisodes = list }
        
        // Update Play Button state if we just switched seasons manually
        // We only do this if the smart "Next Up" isn't locking us elsewhere
        if self.nextUpEpisode?.season == season {
            // Keep the smart button
        } else {
            // We are exploring a different season, reset button to generic play of first ep
            if let first = list.first {
                self.playButtonLabel = "Play S\(season) E\(first.number)"
                self.nextUpEpisode = first
                self.playButtonIcon = "play.fill"
            }
        }
    }
    
    // MARK: - Version Metadata Logic
    
    private func processVersions(_ structs: [ChannelStruct]) -> [VersionOption] {
        let preferredLang = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "English"
        let preferredRes = UserDefaults.standard.string(forKey: "preferredResolution") ?? "4K"
        let maxRes = UserDefaults.standard.string(forKey: "maxStreamResolution") ?? "Unlimited"
        
        return structs.compactMap { ch -> VersionOption? in
            var quality = ch.quality ?? "HD"
            var language = "Unknown"
            
            if let sid = ch.seriesId, let parentInfo = self.seriesMetadataMap[sid] {
                if let pLang = parentInfo.language { language = pLang }
                if !parentInfo.quality.isEmpty { quality = parentInfo.quality }
            }
            
            let epInfo = TitleNormalizer.parse(rawTitle: ch.canonicalTitle ?? ch.title)
            if language == "Unknown", let eLang = epInfo.language { language = eLang }
            if quality == "HD" && !epInfo.quality.isEmpty { quality = epInfo.quality }
            
            if maxRes != "Unlimited" {
                let is4K = quality.contains("4K") || quality.contains("UHD") || quality.contains("2160")
                let is1080p = quality.contains("1080") || quality.contains("FHD")
                
                if maxRes == "1080p" && is4K { return nil }
                if maxRes == "720p" && (is4K || is1080p) { return nil }
            }
            
            var score = 0
            if quality.contains("4K") { score += 4000 } else if quality.contains("1080") { score += 1080 }
            if language.localizedCaseInsensitiveContains(preferredLang) { score += 10000 }
            if quality.localizedCaseInsensitiveContains(preferredRes) { score += 5000 }
            
            return VersionOption(
                id: ch.url,
                channelStruct: ch,
                quality: quality,
                language: language,
                score: score
            )
        }.sorted { $0.score > $1.score }
    }
    
    private func processMovieVersions(structs: [ChannelStruct]) {
        self.movieVersions = processVersions(structs)
        if self.movieVersions.isEmpty && !structs.isEmpty {
            let fallback = structs.map { ch -> VersionOption in
                let q = ch.quality ?? "HD"
                return VersionOption(id: ch.url, channelStruct: ch, quality: q, language: "Unknown", score: 0)
            }
            self.movieVersions = fallback
        }
    }
    
    // MARK: - Playback Triggers
    
    func onPlayEpisode(_ episode: MergedEpisode) {
        if episode.versions.count > 1 {
            self.pickerTitle = episode.displayTitle
            self.pickerOptions = episode.versions
            self.onPickerSelect = { [weak self] selectedStruct in
                self?.triggerPlay(structItem: selectedStruct)
            }
            self.showVersionPicker = true
        } else if let only = episode.versions.first {
            triggerPlay(structItem: only.channelStruct)
        }
    }
    
    func onPlayMovie() {
        if movieVersions.count > 1 {
            self.pickerTitle = "Select Version"
            self.pickerOptions = movieVersions
            self.onPickerSelect = { [weak self] selectedStruct in
                self?.triggerPlay(structItem: selectedStruct)
            }
            self.showVersionPicker = true
        } else if let only = movieVersions.first {
            triggerPlay(structItem: only.channelStruct)
        } else {
            triggerPlay(structItem: ChannelStruct(entity: channel))
        }
    }
    
    private func triggerPlay(structItem: ChannelStruct) {
        guard let repo = repository else { return }
        let ctx = repo.container.viewContext
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.predicate = NSPredicate(format: "url == %@", structItem.url)
        req.fetchLimit = 1
        
        if let obj = try? ctx.fetch(req).first {
            NotificationCenter.default.post(name: NSNotification.Name("PlayChannel"), object: obj)
        }
    }
    
    // MARK: - Helpers
    
    private func getCompositeProgress(for structs: [ChannelStruct]) async -> (Bool, Double) {
        guard let repo = repository else { return (false, 0) }
        let urls = structs.map { $0.url }
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
    
    private func fetchMetadata() async {
        let info = TitleNormalizer.parse(rawTitle: channel.canonicalTitle ?? channel.title)
        async let tmdb = tmdbClient.findBestMatch(title: info.normalizedTitle, year: info.year, type: channel.type == "series" ? "series" : "movie")
        async let omdb = omdbClient.getSeriesMetadata(title: info.normalizedTitle, year: info.year)
        let (tmdbMatch, omdbData) = await (tmdb, omdb)
        
        if let omdb = omdbData { self.omdbDetails = omdb }
        
        if let match = tmdbMatch {
            if channel.type == "series" {
                if let details = try? await tmdbClient.getTvDetails(id: match.id) {
                    self.tmdbDetails = details
                    if let cast = details.aggregateCredits?.cast { self.cast = cast }
                }
            } else {
                if let details = try? await tmdbClient.getMovieDetails(id: match.id) {
                    self.tmdbDetails = details
                    if let cast = details.credits?.cast { self.cast = cast }
                }
            }
        }
        
        var newBg: URL? = nil
        let isSeries = (channel.type == "series" || channel.type == "series_episode")
        
        if isSeries {
            if let poster = self.omdbDetails?.poster, poster != "N/A" {
                newBg = URL(string: getHighResOmdbImage(poster))
            } else if let bg = self.tmdbDetails?.backdropPath {
                newBg = URL(string: "https://image.tmdb.org/t/p/original\(bg)")
            }
        } else {
            if let bg = self.tmdbDetails?.backdropPath {
                newBg = URL(string: "https://image.tmdb.org/t/p/original\(bg)")
            } else if let poster = self.omdbDetails?.poster, poster != "N/A" {
                newBg = URL(string: getHighResOmdbImage(poster))
            }
        }
        
        if let highRes = newBg { self.backgroundUrl = highRes }
    }
    
    private func getHighResOmdbImage(_ url: String) -> String {
        return url.replacingOccurrences(of: "_SX300", with: "")
                  .replacingOccurrences(of: "_SX3000", with: "")
    }
    
    func toggleFavorite() {
        repository?.toggleFavorite(channel)
        self.isFavorite.toggle()
    }
    
    func toggleWatchlist() {
        repository?.toggleWatchlist(channel)
        self.isInWatchlist.toggle()
    }
    
    func onPlaySmartTarget() {
        if let next = nextUpEpisode { onPlayEpisode(next) } else { onPlayMovie() }
    }
}
