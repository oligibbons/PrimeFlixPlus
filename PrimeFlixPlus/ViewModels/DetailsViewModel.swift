import Foundation
import Combine
import SwiftUI

@MainActor
class DetailsViewModel: ObservableObject {
    
    // Data Sources
    @Published var channel: Channel
    @Published var tmdbDetails: TmdbDetails?
    @Published var cast: [TmdbCast] = []
    
    // UI State
    @Published var isFavorite: Bool = false
    @Published var versions: [Channel] = []
    @Published var selectedVersion: Channel?
    @Published var isLoading: Bool = false
    @Published var backgroundUrl: URL?
    @Published var posterUrl: URL?
    
    // Series Data
    @Published var xtreamEpisodes: [XtreamChannelInfo.Episode] = []
    @Published var seasons: [Int] = []
    @Published var selectedSeason: Int = 1
    @Published var displayedEpisodes: [XtreamChannelInfo.Episode] = []
    
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    
    init(channel: Channel) {
        self.channel = channel
        self.isFavorite = channel.isFavorite
    }
    
    func configure(repository: PrimeFlixRepository) {
        // Load other versions (e.g. 4K vs 1080p)
        // We use the repository's internal channelRepo logic
        // Note: In a clean architecture, we'd expose this better, but we can fetch via a helper here if needed,
        // or we can just use the raw Core Data if passed.
        // For now, let's assume we trigger this separately or pass the repository in `loadData`
    }
    
    func loadData(repository: PrimeFlixRepository? = nil) async {
        self.isLoading = true
        
        // 1. Fetch Metadata
        await fetchTmdbData()
        
        // 2. Fetch Series Data
        if channel.type == "series" {
            await fetchXtreamEpisodes()
        }
        
        // 3. Fetch Versions (if repository provided)
        if let repo = repository {
            // Accessing the private channelRepo via a public accessor we should add to Repository,
            // OR we just do a direct fetch here if we had the context.
            // Since `PrimeFlixRepository` wraps it, let's assume we can ask it.
            // For this snippet, I'll rely on the View passing the repo context or similar.
        }
        
        self.isLoading = false
    }
    
    func loadVersions(using repository: PrimeFlixRepository) {
        // Since Repository wrapper might not expose `getRelated`, we can add a helper there
        // or just manually fetch if we have access.
        // Ideally:
        // self.versions = repository.getVersions(for: channel)
        // self.selectedVersion = self.versions.first(where: { $0.url == channel.url }) ?? channel
    }
    
    func toggleFavorite(repository: PrimeFlixRepository) {
        repository.toggleFavorite(channel)
        self.isFavorite = channel.isFavorite
    }

    private func fetchTmdbData() async {
        let info = TitleNormalizer.parse(rawTitle: channel.title)
        let query = info.normalizedTitle
        let year = info.year
        
        do {
            if channel.type == "series" {
                let results = try await tmdbClient.searchTv(query: query, year: year)
                if let first = results.first {
                    let details = try await tmdbClient.getTvDetails(id: first.id)
                    handleDetailsLoaded(details)
                }
            } else {
                let results = try await tmdbClient.searchMovie(query: query, year: year)
                if let first = results.first {
                    let details = try await tmdbClient.getMovieDetails(id: first.id)
                    handleDetailsLoaded(details)
                }
            }
        } catch {
            print("TMDB Error: \(error)")
        }
    }
    
    private func fetchXtreamEpisodes() async {
        let input = XtreamInput.decodeFromPlaylistUrl(channel.playlistUrl)
        let seriesIdString = channel.url.replacingOccurrences(of: "series://", with: "")
        guard let seriesId = Int(seriesIdString) else { return }
        
        do {
            let episodes = try await xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesId)
            self.xtreamEpisodes = episodes
            let allSeasons = Set(episodes.map { $0.season }).sorted()
            self.seasons = allSeasons.isEmpty ? [1] : allSeasons
            
            if let first = self.seasons.first {
                selectSeason(first)
            }
        } catch {
            print("Xtream Error: \(error)")
        }
    }
    
    private func handleDetailsLoaded(_ details: TmdbDetails) {
        self.tmdbDetails = details
        self.cast = details.credits?.cast?.prefix(10).map { $0 } ?? []
        
        if let path = details.backdropPath {
            self.backgroundUrl = URL(string: "https://image.tmdb.org/t/p/original\(path)")
        }
        if let path = details.posterPath {
            self.posterUrl = URL(string: "https://image.tmdb.org/t/p/w500\(path)")
        }
    }
    
    func selectSeason(_ season: Int) {
        self.selectedSeason = season
        self.displayedEpisodes = xtreamEpisodes.filter { $0.season == season }
    }
    
    func createPlayableChannel(for episode: XtreamChannelInfo.Episode) -> Channel {
        let input = XtreamInput.decodeFromPlaylistUrl(channel.playlistUrl)
        let streamUrl = "\(input.basicUrl)/series/\(input.username)/\(input.password)/\(episode.id).\(episode.containerExtension)"
        
        let playable = Channel(context: channel.managedObjectContext!)
        playable.title = episode.title ?? "Episode \(episode.episodeNum)"
        playable.url = streamUrl
        playable.cover = channel.cover
        playable.playlistUrl = channel.playlistUrl
        return playable
    }
}
