import Foundation
import Combine

@MainActor
class DetailsViewModel: ObservableObject {
    
    // Data Sources
    @Published var channel: Channel
    @Published var tmdbDetails: TmdbDetails?
    @Published var cast: [TmdbCast] = []
    
    // Playback Data (From Xtream)
    @Published var xtreamEpisodes: [XtreamChannelInfo.Episode] = []
    @Published var seasons: [Int] = []
    @Published var selectedSeason: Int = 1
    @Published var displayedEpisodes: [XtreamChannelInfo.Episode] = []
    
    // UI State
    @Published var isLoading: Bool = false
    @Published var backgroundUrl: URL?
    @Published var posterUrl: URL?
    
    private let tmdbClient = TmdbClient()
    private let xtreamClient = XtreamClient()
    
    init(channel: Channel) {
        self.channel = channel
    }
    
    func loadData() async {
        self.isLoading = true
        
        // 1. Parallel Fetch: Metadata + Playable Streams
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTmdbData() }
            
            if channel.type == "series" {
                group.addTask { await self.fetchXtreamEpisodes() }
            }
        }
        
        self.isLoading = false
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
        // We need credentials to fetch episodes.
        // We extract them from the channel's playlist URL or pass them in.
        // For now, we re-decode the input from the stored URL.
        let input = XtreamInput.decodeFromPlaylistUrl(channel.playlistUrl)
        
        // The channel.url for a series is usually a placeholder "series://ID"
        // We extract the ID.
        let seriesIdString = channel.url.replacingOccurrences(of: "series://", with: "")
        guard let seriesId = Int(seriesIdString) else { return }
        
        do {
            let episodes = try await xtreamClient.getSeriesEpisodes(input: input, seriesId: seriesId)
            self.xtreamEpisodes = episodes
            
            // Extract unique seasons
            let allSeasons = Set(episodes.map { $0.season }).sorted()
            self.seasons = allSeasons.isEmpty ? [1] : allSeasons
            
            // Select first season by default
            if let first = self.seasons.first {
                // FIXED: Removed await
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
    
    /// Converts an Xtream Episode into a playable Channel object
    func createPlayableChannel(for episode: XtreamChannelInfo.Episode) -> Channel {
        let input = XtreamInput.decodeFromPlaylistUrl(channel.playlistUrl)
        let streamUrl = "\(input.basicUrl)/series/\(input.username)/\(input.password)/\(episode.id).\(episode.containerExtension)"
        
        // Create a temporary Channel object for the player
        // We use the existing context just for initialization, strictly for UI passing
        let playable = Channel(context: channel.managedObjectContext!)
        playable.title = episode.title ?? "Episode \(episode.episodeNum)"
        playable.url = streamUrl
        playable.cover = channel.cover // Inherit series cover
        playable.playlistUrl = channel.playlistUrl
        return playable
    }
}
