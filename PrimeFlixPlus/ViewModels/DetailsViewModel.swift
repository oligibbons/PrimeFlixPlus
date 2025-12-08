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
    
    // UPDATED: Now passes ChannelStruct to allow safe handling from Views
    @Published var onPickerSelect: ((ChannelStruct) -> Void)? = nil
    
    @Published var playButtonLabel: String = "Play"
    @Published var nextUpEpisode: MergedEpisode? = nil
    @Published var playButtonIcon: String = "play.fill"
    
    // --- Dependencies ---
    private let tmdbClient = TmdbClient()
    private let omdbClient = OmdbClient()
    private let xtreamClient = XtreamClient()
    private var repository: PrimeFlixRepository?
    
    // --- Internal ---
    private var seriesEcosystem: [Int: [Int: [ChannelStruct]]] = [:]
    private var tmdbSeasonCache: [Int: [TmdbEpisode]] = [:]
    
    // Stores metadata derived from Parent Containers
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
                    // FIX: Static call using 'DetailsViewModel' to avoid 'self' capture issues
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
        
        if isSeriesType {
            await processSeriesData(episodes: result.episodes)
        } else {
            processMovieVersions(structs: result.versions)
        }
        
        await fetchMetadata()
        await recalculateSmartPlay()
        
        withAnimation { self.isLoading = false }
        withAnimation(.easeIn(duration: 0.5)) { self.backdropOpacity = 1.0 }
    }
    
    // MARK: - Ingestion Logic
    
    /// Static helper to ingest episodes safely on a background context
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
    
    // MARK: - Series Processing
    
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
        
        if !seasons.contains(selectedSeason), let first = seasons.first {
            self.selectedSeason = first
        }
        
        await loadSeasonContent(selectedSeason)
    }
    
    func loadSeasonContent(_ season: Int) async {
        self.selectedSeason = season
        guard let epMap = seriesEcosystem[season] else { return }
        
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
    
    // MARK: - Version Metadata Logic
    
    private func processVersions(_ structs: [ChannelStruct]) -> [VersionOption] {
        let preferredLang = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "English"
        let preferredRes = UserDefaults.standard.string(forKey: "preferredResolution") ?? "4K"
        
        return structs.map { ch in
            var quality = ch.quality ?? "HD"
            var language = "Unknown"
            
            if let sid = ch.seriesId, let parentInfo = self.seriesMetadataMap[sid] {
                if let pLang = parentInfo.language { language = pLang }
                if !parentInfo.quality.isEmpty { quality = parentInfo.quality }
            }
            
            let epInfo = TitleNormalizer.parse(rawTitle: ch.canonicalTitle ?? ch.title)
            if language == "Unknown", let eLang = epInfo.language { language = eLang }
            if quality == "HD" && !epInfo.quality.isEmpty { quality = epInfo.quality }
            
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
            // Fallback to current channel
            triggerPlay(structItem: ChannelStruct(entity: channel))
        }
    }
    
    // Safe Trigger using Struct
    private func triggerPlay(structItem: ChannelStruct) {
        guard let repo = repository else { return }
        // Re-fetch object on Main Context for the Player
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
    
    func toggleFavorite() {
        repository?.toggleFavorite(channel)
        self.isFavorite.toggle()
    }
    
    func onPlaySmartTarget() {
        if let next = nextUpEpisode { onPlayEpisode(next) } else { onPlayMovie() }
    }
}

// Helper Extension for playback reconstruction
extension ChannelStruct {
    func toChannel(context: NSManagedObjectContext) -> Channel {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.predicate = NSPredicate(format: "url == %@", self.url)
        req.fetchLimit = 1
        if let existing = try? context.fetch(req).first {
            return existing
        }
        return Channel(context: context, playlistUrl: playlistUrl, url: url, title: title, group: group, type: type)
    }
}
