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
    
    // --- Versioning (Movies) ---
    // UPDATED: Now holds fully labeled options
    struct VersionOption: Identifiable {
        var id: String { channel.url }
        let label: String
        let channel: Channel
    }
    @Published var availableVersions: [VersionOption] = []
    @Published var selectedVersion: Channel?
    @Published var showVersionSelector: Bool = false
    
    // --- Smart Play State ---
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
    private var aggregatedEpisodes: [String: [EpisodeVersion]] = [:]
    
    // MARK: - Models (Internal)
    
    struct EpisodeVersion: Identifiable {
        let id = UUID()
        let streamId: String
        let containerExtension: String
        let qualityLabel: String // Display: "English 4K"
        let url: String
        let playlistUrl: String
    }
    
    struct MergedEpisode: Identifiable {
        let id: String
        let season: Int
        let number: Int
        let title: String
        let overview: String
        let stillPath: URL?
        var versions: [EpisodeVersion]
        
        var isWatched: Bool = false
        var progress: Double = 0.0
        
        var displayTitle: String { "S\(season) • E\(number) - \(title)" }
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
        
        let title = channel.canonicalTitle ?? channel.title
        let type = channel.type
        
        // 1. Fetch Versions (Using New Service)
        await fetchVersions()
        
        // 2. Fetch TMDB
        await fetchTmdbData(title: title, type: type)
        
        // 3. Series Data
        if type == "series" {
            await fetchAndAggregateEpisodes()
        }
        
        // 4. Calculate Up Next
        await recalculateSmartPlay()
    }
    
    // MARK: - Versioning Logic (Updated)
    
    private func fetchVersions() async {
        guard let repo = repository else { return }
        let oid = channel.objectID
        
        // Fetch raw channels from Service
        let rawChannels: [Channel] = await Task.detached(priority: .userInitiated) {
            let context = repo.container.newBackgroundContext()
            return context.performAndWait {
                let service = VersioningService(context: context)
                if let bgChannel = try? context.existingObject(with: oid) as? Channel {
                    let results = service.getVersions(for: bgChannel)
                    // Map ObjectIDs back to Main Context
                    let ids = results.map { $0.objectID }
                    return ids.compactMap { try? repo.container.viewContext.existingObject(with: $0) as? Channel }
                }
                return []
            }
        }.value
        
        // Map to VersionOptions with Smart Labels
        self.availableVersions = rawChannels.map { ch in
            VersionOption(
                label: self.generateSmartLabel(for: ch),
                channel: ch
            )
        }
        
        // Sort: Preferred Language First, then Resolution
        let prefLang = settings.preferredLanguage
        self.availableVersions.sort {
            let l1 = $0.label.contains(prefLang) ? 1 : 0
            let l2 = $1.label.contains(prefLang) ? 1 : 0
            if l1 != l2 { return l1 > l2 }
            return $0.label > $1.label // 4K > 1080p roughly
        }
        
        if self.selectedVersion == nil {
            self.selectedVersion = self.availableVersions.first?.channel ?? self.channel
        }
    }
    
    func userSelectedVersion(_ channel: Channel) {
        self.selectedVersion = channel
        self.showVersionSelector = false
    }
    
    // MARK: - Smart Label Generator
    
    private func generateSmartLabel(for channel: Channel) -> String {
        let raw = channel.canonicalTitle ?? channel.title
        let info = TitleNormalizer.parse(rawTitle: raw)
        
        // Language
        let lang = info.language ?? "Default"
        
        // Quality
        var qual = info.quality
        if qual.isEmpty || qual == "SD" {
            // Fallback check on channel quality field
            qual = channel.quality ?? "SD"
        }
        
        return "\(lang) | \(qual)"
    }
    
    // MARK: - Series Aggregation (Updated)
    
    private func fetchAndAggregateEpisodes() async {
        let sources = availableVersions.isEmpty ? [VersionOption(label: "Default", channel: channel)] : availableVersions
        let preferredLang = settings.preferredLanguage.lowercased()
        
        var rawEpisodes: [(String, EpisodeVersion)] = []
        
        await withTaskGroup(of: [(String, EpisodeVersion)].self) { group in
            for variant in sources {
                guard let seriesIdStr = variant.channel.seriesId, let seriesIdInt = Int(seriesIdStr) else { continue }
                
                group.addTask {
                    let input = XtreamInput.decodeFromPlaylistUrl(variant.channel.playlistUrl)
                    guard let episodes = try? await self.xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesIdInt) else { return [] }
                    
                    return episodes.map { ep in
                        let key = String(format: "S%02dE%02d", ep.season, ep.episodeNum)
                        let streamUrl = "\(input.basicUrl)/series/\(input.username)/\(input.password)/\(ep.id).\(ep.containerExtension)"
                        
                        // Use the Variant's Label (e.g. "English 4K") derived earlier
                        let label = variant.label
                        
                        let version = EpisodeVersion(
                            streamId: ep.id,
                            containerExtension: ep.containerExtension,
                            qualityLabel: label,
                            url: streamUrl,
                            playlistUrl: variant.channel.playlistUrl
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
        
        // Sort Episodes by Language Preference
        for (key, _) in newAggregation {
            newAggregation[key]?.sort { v1, v2 in
                let q1 = v1.qualityLabel.lowercased()
                let q2 = v2.qualityLabel.lowercased()
                let v1Match = q1.contains(preferredLang)
                let v2Match = q2.contains(preferredLang)
                
                if v1Match && !v2Match { return true }
                if !v1Match && v2Match { return false }
                
                return q1 > q2 // Fallback to string sort (4K > 1080p usually works)
            }
        }
        
        self.aggregatedEpisodes = newAggregation
        self.seasons = discoveredSeasons.sorted()
        
        if let first = self.seasons.first {
            await selectSeason(first)
        }
    }
    
    // MARK: - Rest of Logic (Unchanged but included for completeness)
    
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
        
        withAnimation { self.displayedEpisodes = merged }
        await updateProgressForDisplayedEpisodes()
    }
    
    func onPlayEpisodeClicked(_ episode: MergedEpisode) {
        self.episodeToPlay = episode
        self.showEpisodeVersionPicker = true
    }
    
    func getPlayableChannel(version: EpisodeVersion, metadata: MergedEpisode) -> Channel {
        let playable = Channel(context: repository!.container.viewContext)
        playable.url = version.url
        playable.title = "\(channel.title) - \(metadata.displayTitle)"
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
    
    private func fetchTmdbData(title: String, type: String) async {
        let info = TitleNormalizer.parse(rawTitle: title)
        do {
            if type == "series" {
                let results = try await tmdbClient.searchTv(query: info.normalizedTitle, year: info.year)
                if let best = results.first {
                    let details = try await tmdbClient.getTvDetails(id: best.id)
                    await MainActor.run { self.applyTmdbData(details) }
                }
            } else {
                let results = try await tmdbClient.searchMovie(query: info.normalizedTitle, year: info.year)
                if let best = results.first {
                    let details = try await tmdbClient.getMovieDetails(id: best.id)
                    await MainActor.run { self.applyTmdbData(details) }
                }
            }
        } catch { print("TMDB Error: \(error)") }
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
    
    var trailerUrl: URL? {
        guard let video = tmdbDetails?.videos?.results.first(where: { $0.isTrailer }) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(video.key)")
    }
    
    var similarContent: [TmdbMovieResult] {
        return tmdbDetails?.similar?.results.prefix(10).filter { $0.posterPath != nil } ?? []
    }
}
