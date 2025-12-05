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
    }
    
    func loadData() async {
        withAnimation { self.isLoading = false }
        withAnimation(.easeIn(duration: 0.5)) { self.backdropOpacity = 1.0 }
        
        guard let repo = repository else { return }
        let channelObjectID = channel.objectID
        let channelRawTitle = channel.canonicalTitle ?? channel.title
        let channelType = channel.type
        
        // 1. Load Versions in Background
        Task.detached(priority: .userInitiated) {
            let context = repo.container.newBackgroundContext()
            var versionIDs: [NSManagedObjectID] = []
            context.performAndWait {
                let bgRepo = ChannelRepository(context: context)
                if let bgChannel = try? context.existingObject(with: channelObjectID) as? Channel {
                    versionIDs = bgRepo.getVersions(for: bgChannel).map { $0.objectID }
                }
            }
            let safeIDs = versionIDs
            await MainActor.run { self.processVersions(versionIDs: safeIDs) }
        }
        
        // 2. Parallel Fetch: TMDB Metadata & Xtream Series Data
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTmdbData(title: channelRawTitle, type: channelType) }
            if channelType == "series" { group.addTask { await self.fetchAggregatedSeriesData() } }
        }
    }
    
    // MARK: - Playback Logic
    
    func getSmartPlayTarget() -> Channel? {
        if channel.type == "movie" { return selectedVersion }
        if channel.type == "series" {
            let sorted = xtreamEpisodes.sorted {
                if $0.season != $1.season { return $0.season < $1.season }
                return $0.episodeNum < $1.episodeNum
            }
            if let firstEp = sorted.first { return constructChannelForEpisode(firstEp) }
        }
        return nil
    }
    
    private func constructChannelForEpisode(_ ep: XtreamChannelInfo.Episode) -> Channel? {
        let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
        guard let sourceUrl = episodeSourceMap[key] else { return nil }
        
        let input = XtreamInput.decodeFromPlaylistUrl(sourceUrl)
        
        // Ensure series uses correct endpoint
        let streamUrl = "\(input.basicUrl)/series/\(input.username)/\(input.password)/\(ep.id).\(ep.containerExtension)"
        
        guard let context = channel.managedObjectContext else { return nil }
        let ch = Channel(context: context)
        ch.url = streamUrl
        ch.title = "\(channel.title) - S\(ep.season)E\(ep.episodeNum)"
        ch.type = "series_episode"
        ch.playlistUrl = sourceUrl
        ch.cover = channel.cover
        
        return ch
    }
    
    func createPlayableChannel(for episode: MergedEpisode) -> Channel {
        return constructChannelForEpisode(episode.streamInfo) ?? channel
    }
    
    // MARK: - Versioning
    private func processVersions(versionIDs: [NSManagedObjectID]) {
        guard let context = channel.managedObjectContext else { return }
        let versions = versionIDs.compactMap { try? context.existingObject(with: $0) as? Channel }
        self.availableVersions = versions
        resolveBestVersion()
        if channel.type == "series" && !versions.isEmpty { Task { await fetchAggregatedSeriesData() } }
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
        if channel.type == "series" { Task { await fetchAggregatedSeriesData() } }
    }
    
    // MARK: - Helper Logic
    private func checkWatchHistory() {
        guard let repo = repository, let target = selectedVersion else { return }
        let targetUrl = target.url
        Task.detached {
            let context = repo.container.newBackgroundContext()
            let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            request.predicate = NSPredicate(format: "channelUrl == %@", targetUrl)
            request.fetchLimit = 1
            if let result = (try? context.fetch(request))?.first {
                let pos = Double(result.position) / 1000.0
                let dur = Double(result.duration) / 1000.0
                await MainActor.run {
                    self.resumePosition = pos
                    self.resumeDuration = dur
                    let pct = dur > 0 ? pos / dur : 0
                    self.hasWatchHistory = pct > 0.02 && pct < 0.95
                }
            }
        }
    }
    
    // MARK: - Smart TMDB Fetching (Improved)
    
    private func fetchTmdbData(title: String, type: String) async {
        let info = TitleNormalizer.parse(rawTitle: title)
        
        // STRATEGY: Define multiple attempts to maximize match rate.
        // 1. Strict: Uses Normalized Title + Year (High precision)
        // 2. Loose: Uses Normalized Title ONLY (Fixes wrong year in filename)
        let searchStrategies: [(query: String, year: String?)] = [
            (info.normalizedTitle, info.year),
            (info.normalizedTitle, nil)
        ]
        
        for (query, year) in searchStrategies {
            // Skip invalid queries
            if query.isEmpty { continue }
            
            do {
                var foundId: Int?
                
                if type == "series" {
                    let results = try await tmdbClient.searchTv(query: query, year: year)
                    foundId = results.first?.id
                } else {
                    let results = try await tmdbClient.searchMovie(query: query, year: year)
                    foundId = results.first?.id
                }
                
                // If we found a match, fetch details and STOP searching.
                if let id = foundId {
                    if type == "series" {
                        let details = try await tmdbClient.getTvDetails(id: id)
                        await MainActor.run { self.handleDetailsLoaded(details) }
                    } else {
                        let details = try await tmdbClient.getMovieDetails(id: id)
                        await MainActor.run { self.handleDetailsLoaded(details) }
                    }
                    return // Success!
                }
                
            } catch {
                print("⚠️ TMDB Search Attempt Failed for '\(query)' (Year: \(year ?? "None")): \(error.localizedDescription)")
            }
        }
        
        print("❌ TMDB: No match found for '\(title)' after all strategies.")
    }
    
    private func handleDetailsLoaded(_ details: TmdbDetails) {
        self.tmdbDetails = details
        if let bg = details.backdropPath { self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(bg)") }
        if let cast = details.aggregateCredits?.cast ?? details.credits?.cast { self.cast = cast.prefix(12).map { $0 } }
        
        // REFRESH EPISODES: If series data loaded *after* Xtream data, we need to re-merge to get metadata.
        if channel.type == "series" {
            Task { await self.selectSeason(self.selectedSeason) }
        }
    }
    
    private func fetchAggregatedSeriesData() async {
        let versionsSnapshot = availableVersions.isEmpty ? [channel] : availableVersions
        let versionData = versionsSnapshot.map { (url: $0.url, playlistUrl: $0.playlistUrl) }
        let client = self.xtreamClient
        
        let result = await Task.detached(priority: .userInitiated) { () -> ([XtreamChannelInfo.Episode], [String: String], [Int]) in
            var allEpisodes: [(XtreamChannelInfo.Episode, String)] = []
            
            await withTaskGroup(of: [(XtreamChannelInfo.Episode, String)].self) { group in
                for vData in versionData {
                    let vDataCopy = vData
                    group.addTask {
                        let input = XtreamInput.decodeFromPlaylistUrl(vDataCopy.playlistUrl)
                        let seriesIdString = vDataCopy.url.replacingOccurrences(of: "series://", with: "")
                        guard let seriesId = Int(seriesIdString) else { return [] }
                        return (try? await client.getSeriesEpisodes(input: input, seriesId: seriesId))?.map { ($0, vDataCopy.playlistUrl) } ?? []
                    }
                }
                for await res in group { allEpisodes.append(contentsOf: res) }
            }
            
            var uniqueEpisodes: [String: (XtreamChannelInfo.Episode, String)] = [:]
            for (ep, source) in allEpisodes {
                let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
                if uniqueEpisodes[key] == nil { uniqueEpisodes[key] = (ep, source) }
            }
            let finalEpisodes = uniqueEpisodes.values.map { $0.0 }
            let finalMap = uniqueEpisodes.mapValues { $0.1 }
            let finalSeasons = Set(finalEpisodes.map { $0.season }).sorted()
            
            return (finalEpisodes, finalMap, finalSeasons)
        }.value
        
        self.xtreamEpisodes = result.0
        self.episodeSourceMap = result.1
        self.seasons = result.2.isEmpty ? [1] : result.2
        
        await MainActor.run {
            if let first = self.seasons.first {
                Task { await self.selectSeason(first) }
            }
        }
    }
    
    func selectSeason(_ season: Int) async {
        self.selectedSeason = season
        
        // Metadata Fetch: Ensure we have TMDB data for this season
        if tmdbEpisodes[season] == nil, let tmdbId = tmdbDetails?.id {
            if let seasonDetails = try? await tmdbClient.getTvSeason(tvId: tmdbId, seasonNumber: season) {
                tmdbEpisodes[season] = seasonDetails.episodes
            }
        }
        
        // Merge Logic: Combine Xtream (File) with TMDB (Metadata)
        let merged = xtreamEpisodes.filter { $0.season == season }.sorted { $0.episodeNum < $1.episodeNum }.map { xEp -> MergedEpisode in
            let tEp = tmdbEpisodes[season]?.first(where: { $0.episodeNumber == xEp.episodeNum })
            let key = String(format: "S%02dE%02d", xEp.season, xEp.episodeNum)
            
            return MergedEpisode(
                id: xEp.id,
                number: xEp.episodeNum,
                title: tEp?.name ?? xEp.title ?? "Episode \(xEp.episodeNum)",
                overview: tEp?.overview ?? "",
                imageUrl: tEp?.stillPath.map { URL(string: "https://image.tmdb.org/t/p/w500\($0)")! },
                streamInfo: xEp,
                sourcePlaylistUrl: episodeSourceMap[key] ?? channel.playlistUrl,
                isWatched: false
            )
        }
        
        withAnimation {
            self.displayedEpisodes = merged
        }
    }
    
    func toggleFavorite() {
        repository?.toggleFavorite(channel)
        self.isFavorite.toggle()
    }
}
