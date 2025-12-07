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
    
    // --- Versioning (Movies & Series Roots) ---
    @Published var availableVersions: [Channel] = []
    @Published var selectedVersion: Channel?
    @Published var showVersionSelector: Bool = false
    
    // --- Smart Play State ---
    @Published var smartPlayTarget: MergedEpisode? = nil
    @Published var playButtonLabel: String = "Play Now"
    @Published var playButtonIcon: String = "play.fill"
    @Published var hasWatchHistory: Bool = false
    
    // --- Series/Episode State ---
    @Published var seasons: [Int] = []
    @Published var selectedSeason: Int = 1
    @Published var displayedEpisodes: [MergedEpisode] = []
    
    // --- Interaction Triggers ---
    @Published var episodeToPlay: MergedEpisode? = nil
    @Published var showEpisodeVersionPicker: Bool = false
    
    // --- Dependencies ---
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    private var repository: PrimeFlixRepository?
    private let settings = SettingsViewModel()
    
    // --- Internal Storage ---
    private var tmdbEpisodes: [Int: [TmdbEpisode]] = [:]
    private var aggregatedEpisodes: [String: [EpisodeVersion]] = [:]
    
    // MARK: - Models
    
    struct EpisodeVersion: Identifiable {
        let id = UUID()
        let streamId: String
        let containerExtension: String
        let qualityLabel: String
        let url: String
        let playlistUrl: String
    }
    
    struct MergedEpisode: Identifiable {
        let id: String // Key: "S01E01"
        let season: Int
        let number: Int
        let title: String
        let overview: String
        let stillPath: URL?
        var versions: [EpisodeVersion]
        
        var isWatched: Bool = false
        var progress: Double = 0.0
        
        var displayTitle: String {
            return "S\(season) • E\(number) - \(title)"
        }
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
        
        let title = channel.canonicalTitle ?? channel.title
        let type = channel.type
        
        // 1. Fetch Versions (Background)
        await fetchVersions()
        
        // 2. Fetch TMDB Data (With Fuzzy Fallback)
        await fetchTmdbData(title: title, type: type)
        
        // 3. Fetch Series Data (if applicable)
        if type == "series" {
            await fetchAndAggregateEpisodes()
        }
        
        // 4. Calculate "Up Next"
        await recalculateSmartPlay()
    }
    
    // MARK: - Core Data Versions (Fixed for Concurrency)
    private func fetchVersions() async {
        guard let repo = repository else { return }
        let oid = channel.objectID
        
        // Explicitly typed Task to avoid compiler ambiguity
        let versionIDs: [NSManagedObjectID] = await Task.detached(priority: .userInitiated) {
            let context = repo.container.newBackgroundContext()
            return context.performAndWait {
                if let bgChannel = try? context.existingObject(with: oid) as? Channel {
                    let bgRepo = ChannelRepository(context: context)
                    return bgRepo.getVersions(for: bgChannel).map { $0.objectID }
                }
                return []
            }
        }.value
        
        self.availableVersions = versionIDs.compactMap { try? repo.container.viewContext.existingObject(with: $0) as? Channel }
        
        // Pick best version logic can go here if needed, default to first for now
        if self.selectedVersion == nil {
            self.selectedVersion = self.availableVersions.first ?? self.channel
        }
    }
    
    func userSelectedVersion(_ channel: Channel) {
        self.selectedVersion = channel
        self.showVersionSelector = false
    }
    
    // MARK: - Series Aggregation Engine (Fixed Sorting)
    
    private func fetchAndAggregateEpisodes() async {
        let sources = availableVersions.isEmpty ? [channel] : availableVersions
        let preferredLang = settings.preferredLanguage.lowercased()
        
        // Helper struct for TaskGroup
        struct SourceVariant {
            let seriesId: String
            let playlistUrl: String
            let quality: String
            let title: String
        }
        
        let variants = sources.compactMap {
            SourceVariant(
                seriesId: $0.seriesId ?? "",
                playlistUrl: $0.playlistUrl,
                quality: $0.quality ?? "Source",
                title: $0.canonicalTitle ?? $0.title
            )
        }
        
        var rawEpisodes: [(String, EpisodeVersion)] = []
        
        await withTaskGroup(of: [(String, EpisodeVersion)].self) { group in
            for variant in variants {
                guard let seriesIdInt = Int(variant.seriesId) else { continue }
                
                group.addTask {
                    let input = XtreamInput.decodeFromPlaylistUrl(variant.playlistUrl)
                    guard let episodes = try? await self.xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesIdInt) else { return [] }
                    
                    return episodes.map { ep in
                        let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
                        let streamUrl = "\(input.basicUrl)/series/\(input.username)/\(input.password)/\(ep.id).\(ep.containerExtension)"
                        
                        let version = EpisodeVersion(
                            streamId: ep.id,
                            containerExtension: ep.containerExtension,
                            qualityLabel: variant.quality,
                            url: streamUrl,
                            playlistUrl: variant.playlistUrl
                        )
                        return (key, version)
                    }
                }
            }
            
            for await batch in group {
                rawEpisodes.append(contentsOf: batch)
            }
        }
        
        var newAggregation: [String: [EpisodeVersion]] = [:]
        var discoveredSeasons = Set<Int>()
        
        for (key, version) in rawEpisodes {
            newAggregation[key, default: []].append(version)
            if let s = Int(key.prefix(3).dropFirst()) {
                discoveredSeasons.insert(s)
            }
        }
        
        // FIX: Sort versions by LANGUAGE Priority first, then QUALITY
        for (key, _) in newAggregation {
            newAggregation[key]?.sort { v1, v2 in
                // 1. Language Check
                let q1 = v1.qualityLabel.lowercased()
                let q2 = v2.qualityLabel.lowercased()
                
                let v1MatchesLang = q1.contains(preferredLang)
                let v2MatchesLang = q2.contains(preferredLang)
                
                if v1MatchesLang && !v2MatchesLang { return true }
                if !v1MatchesLang && v2MatchesLang { return false }
                
                // 2. Quality Check (4K > 1080p > 720p)
                if q1.contains("4k") && !q2.contains("4k") { return true }
                if q2.contains("4k") && !q1.contains("4k") { return false }
                
                if q1.contains("1080") && !q2.contains("1080") { return true }
                if q2.contains("1080") && !q1.contains("1080") { return false }
                
                return false
            }
        }
        
        self.aggregatedEpisodes = newAggregation
        self.seasons = discoveredSeasons.sorted()
        
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
        
        var merged: [MergedEpisode] = []
        let seasonPrefix = String(format: "S%02d", season)
        let keys = aggregatedEpisodes.keys.filter { $0.hasPrefix(seasonPrefix) }.sorted()
        
        for key in keys {
            guard let versions = aggregatedEpisodes[key] else { continue }
            let epNum = Int(key.suffix(2)) ?? 0
            let tEp = tmdbEpisodes[season]?.first(where: { $0.episodeNumber == epNum })
            
            let item = MergedEpisode(
                id: key,
                season: season,
                number: epNum,
                title: tEp?.name ?? "Episode \(epNum)",
                overview: tEp?.overview ?? "",
                stillPath: tEp?.stillPath.map { URL(string: "https://image.tmdb.org/t/p/w500\($0)")! },
                versions: versions
            )
            merged.append(item)
        }
        
        withAnimation {
            self.displayedEpisodes = merged
        }
        
        await updateProgressForDisplayedEpisodes()
    }
    
    // MARK: - Smart Actions
    
    func onPlayEpisodeClicked(_ episode: MergedEpisode) {
        if episode.versions.count == 1 {
            self.episodeToPlay = episode
            // Trigger playback handled by view via binding to episodeToPlay
        } else {
            self.episodeToPlay = episode
            self.showEpisodeVersionPicker = true
        }
    }
    
    func getPlayableChannel(version: EpisodeVersion, metadata: MergedEpisode) -> Channel {
        let playable = Channel(context: repository!.container.viewContext)
        playable.url = version.url
        playable.title = metadata.displayTitle
        playable.cover = metadata.stillPath?.absoluteString ?? channel.cover
        playable.type = "series_episode"
        playable.playlistUrl = version.playlistUrl
        playable.seriesId = channel.seriesId
        playable.season = Int16(metadata.season)
        playable.episode = Int16(metadata.number)
        return playable
    }
    
    private func updateProgressForDisplayedEpisodes() async {
        guard let repo = repository else { return }
        let allUrls = displayedEpisodes.flatMap { $0.versions.map { $0.url } }
        
        let progressMap: [String: Double] = await Task.detached(priority: .background) {
            let context = repo.container.newBackgroundContext()
            return context.performAndWait {
                var map: [String: Double] = [:]
                let req = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
                req.predicate = NSPredicate(format: "channelUrl IN %@", allUrls)
                if let results = try? context.fetch(req) {
                    for p in results {
                        if p.duration > 0 { map[p.channelUrl] = Double(p.position) / Double(p.duration) }
                    }
                }
                return map
            }
        }.value
        
        var updated = displayedEpisodes
        for i in 0..<updated.count {
            var maxProg = 0.0
            for v in updated[i].versions {
                if let p = progressMap[v.url], p > maxProg { maxProg = p }
            }
            updated[i].progress = maxProg
            updated[i].isWatched = maxProg > 0.95
        }
        self.displayedEpisodes = updated
    }
    
    private func recalculateSmartPlay() async {
        if let first = displayedEpisodes.first, self.smartPlayTarget == nil {
            self.smartPlayTarget = first
            self.playButtonLabel = "Start Series"
        }
    }
    
    // MARK: - TMDB Logic (RESTORED SMART MATCH)
    
    private func fetchTmdbData(title: String, type: String) async {
        let info = TitleNormalizer.parse(rawTitle: title)
        
        // Try strict normalized title first, then raw title if that fails
        let queries = [info.normalizedTitle, title]
        
        for q in queries {
            do {
                if type == "series" {
                    let results = try await tmdbClient.searchTv(query: q, year: info.year)
                    if let best = findBestMatch(results: results, targetTitle: info.normalizedTitle, targetYear: info.year) {
                        let details = try await tmdbClient.getTvDetails(id: best.id)
                        await MainActor.run {
                            self.tmdbDetails = details
                            if let bg = details.backdropPath { self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(bg)") }
                            if let cast = details.aggregateCredits?.cast { self.cast = cast }
                        }
                        return // Success, stop searching
                    }
                } else {
                    let results = try await tmdbClient.searchMovie(query: q, year: info.year)
                    if let best = findBestMatch(results: results, targetTitle: info.normalizedTitle, targetYear: info.year) {
                        let details = try await tmdbClient.getMovieDetails(id: best.id)
                        await MainActor.run {
                            self.tmdbDetails = details
                            if let bg = details.backdropPath { self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(bg)") }
                            if let cast = details.credits?.cast { self.cast = cast }
                        }
                        return // Success
                    }
                }
            } catch {
                print("TMDB Error: \(error)")
            }
        }
    }
    
    // Fuzzy Matcher to ensure we don't miss metadata due to "4K" or "DE" suffixes
    private func findBestMatch<T: Identifiable>(results: [T], targetTitle: String, targetYear: String?) -> T? {
        let target = targetTitle.lowercased()
        
        return results.first { result in
            var title = ""
            var date: String? = nil
            
            if let m = result as? TmdbMovieResult { title = m.title; date = m.releaseDate }
            if let s = result as? TmdbTvResult { title = s.name; date = s.firstAirDate }
            
            let t = title.lowercased()
            
            // Year Check (Strict)
            if let tYear = targetYear, let rYear = date?.prefix(4) {
                if tYear != rYear { return false }
            }
            
            // Title Check (Loose - Fuzzy enough to catch substring matches)
            return t == target || t.contains(target) || target.contains(t)
        }
    }
    
    private func checkWatchHistory() {
        guard let repo = repository, channel.type == "movie" else { return }
        let url = channel.url
        Task.detached {
            let context = repo.container.newBackgroundContext()
            let req = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            req.predicate = NSPredicate(format: "channelUrl == %@", url)
            if let p = try? context.fetch(req).first, p.duration > 0 {
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
}
