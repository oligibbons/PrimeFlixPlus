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
    
    // MARK: - Async Loading
    
    func loadData() async {
        withAnimation { self.isLoading = false }
        withAnimation(.easeIn(duration: 0.5)) { self.backdropOpacity = 1.0 }
        
        guard let repo = repository else { return }
        let channelObjectID = channel.objectID
        
        let channelRawTitle = channel.canonicalTitle ?? channel.title
        let channelType = channel.type
        
        // 1. Fetch Versions
        Task.detached(priority: .userInitiated) {
            let context = repo.container.newBackgroundContext()
            var versionIDs: [NSManagedObjectID] = []
            
            context.performAndWait {
                let bgRepo = ChannelRepository(context: context)
                if let bgChannel = try? context.existingObject(with: channelObjectID) as? Channel {
                    let versions = bgRepo.getVersions(for: bgChannel)
                    versionIDs = versions.map { $0.objectID }
                }
            }
            
            let safeIDs = versionIDs
            await MainActor.run {
                self.processVersions(versionIDs: safeIDs)
            }
        }
        
        // 2. Parallel Data Fetching
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTmdbData(title: channelRawTitle, type: channelType) }
            if channelType == "series" {
                group.addTask { await self.fetchAggregatedSeriesData() }
            }
        }
    }
    
    // MARK: - Smart Playback Logic (NUCLEAR FIX APPLIED)
    
    func getSmartPlayTarget() -> Channel? {
        if channel.type == "movie" {
            return selectedVersion
        }
        
        if channel.type == "series" {
            // Find first episode
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
        // 1. Get Source Playlist Info
        let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
        guard let sourceUrl = episodeSourceMap[key] else { return nil }
        
        let input = XtreamInput.decodeFromPlaylistUrl(sourceUrl)
        
        // 2. Strict Credential Encoding
        let safeUser = input.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? input.username
        let safePass = input.password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? input.password
        
        // 3. Container Swapping (MKV -> MP4)
        var extensionToUse = ep.containerExtension
        if extensionToUse.lowercased() == "mkv" || extensionToUse.lowercased() == "avi" {
            extensionToUse = "mp4"
        }
        
        // FIX APPLIED HERE: Changed /series/ to /movie/
        // Most providers serve raw episode files via the /movie/ endpoint structure.
        let streamUrl = "\(input.basicUrl)/movie/\(safeUser)/\(safePass)/\(ep.id).\(extensionToUse)"
        
        // 4. Construct Temporary Channel Object
        let ch = Channel(context: channel.managedObjectContext!)
        ch.url = streamUrl
        ch.title = "\(channel.title) - S\(ep.season)E\(ep.episodeNum)"
        ch.type = "series_episode"
        ch.playlistUrl = sourceUrl
        ch.cover = channel.cover
        
        print("📺 Series URL Constructed: \(streamUrl)")
        
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
        
        if channel.type == "series" && !versions.isEmpty {
            Task { await fetchAggregatedSeriesData() }
        }
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
        if channel.type == "series" {
            Task { await fetchAggregatedSeriesData() }
        }
    }
    
    // MARK: - Watch History
    
    private func checkWatchHistory() {
        guard let repo = repository, let target = selectedVersion else { return }
        let targetUrl = target.url
        
        Task.detached {
            let context = repo.container.newBackgroundContext()
            let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            request.predicate = NSPredicate(format: "channelUrl == %@", targetUrl)
            request.fetchLimit = 1
            
            var pos: Double = 0
            var dur: Double = 0
            var found = false
            
            context.performAndWait {
                if let results = try? context.fetch(request), let progress = results.first {
                    pos = Double(progress.position) / 1000.0
                    dur = Double(progress.duration) / 1000.0
                    found = true
                }
            }
            
            if found {
                // CRITICAL FIX: Shadow mutable variables with immutable constants
                let finalPos = pos
                let finalDur = dur
                
                await MainActor.run {
                    self.resumePosition = finalPos
                    self.resumeDuration = finalDur
                    let pct = finalDur > 0 ? finalPos / finalDur : 0
                    self.hasWatchHistory = pct > 0.02 && pct < 0.95
                }
            }
        }
    }
    
    // MARK: - Data Fetching
    
    private func fetchTmdbData(title: String, type: String) async {
        let info = TitleNormalizer.parse(rawTitle: title)
        do {
            if type == "series" {
                let results = try await tmdbClient.searchTv(query: info.normalizedTitle, year: info.year)
                if let first = results.first {
                    let details = try await tmdbClient.getTvDetails(id: first.id)
                    await MainActor.run { self.handleDetailsLoaded(details) }
                }
            } else {
                let results = try await tmdbClient.searchMovie(query: info.normalizedTitle, year: info.year)
                if let first = results.first {
                    let details = try await tmdbClient.getMovieDetails(id: first.id)
                    await MainActor.run { self.handleDetailsLoaded(details) }
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
    
    // MARK: - Series Data Aggregation
    
    private func fetchAggregatedSeriesData() async {
        let versionsSnapshot = availableVersions.isEmpty ? [channel] : availableVersions
        let versionData = versionsSnapshot.map { (url: $0.url, playlistUrl: $0.playlistUrl) }
        let client = self.xtreamClient
        
        let result = await Task.detached(priority: .userInitiated) { () -> ([XtreamChannelInfo.Episode], [String: String], [Int]) in
            var allEpisodes: [(XtreamChannelInfo.Episode, String)] = []
            
            await withTaskGroup(of: [(XtreamChannelInfo.Episode, String)].self) { group in
                for vData in versionData {
                    group.addTask {
                        let input = XtreamInput.decodeFromPlaylistUrl(vData.playlistUrl)
                        let seriesIdString = vData.url.replacingOccurrences(of: "series://", with: "")
                        guard let seriesId = Int(seriesIdString) else { return [] }
                        
                        do {
                            let eps = try await client.getSeriesEpisodes(input: input, seriesId: seriesId)
                            return eps.map { ($0, vData.playlistUrl) }
                        } catch {
                            return []
                        }
                    }
                }
                
                for await results in group {
                    allEpisodes.append(contentsOf: results)
                }
            }
            
            var uniqueEpisodes: [String: (XtreamChannelInfo.Episode, String)] = [:]
            for (ep, source) in allEpisodes {
                let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
                if uniqueEpisodes[key] == nil {
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
        
        if tmdbEpisodes[season] == nil, let tmdbId = tmdbDetails?.id {
            if let seasonDetails = try? await tmdbClient.getTvSeason(tvId: tmdbId, seasonNumber: season) {
                tmdbEpisodes[season] = seasonDetails.episodes
            }
        }
        
        let xEps = self.xtreamEpisodes
        let tEps = self.tmdbEpisodes[season] ?? []
        let currentMap = self.episodeSourceMap
        let defaultPlaylist = self.channel.playlistUrl
        
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
