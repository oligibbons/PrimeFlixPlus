import Foundation

/// Handles network communication with Xtream Codes APIs.
actor XtreamClient {
    
    // CHANGED: Use UnsafeSession.shared
    private let session = UnsafeSession.shared
    
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
    
    // MARK: - Public API
    
    func getLiveStreams(input: XtreamInput) async throws -> [XtreamChannelInfo.LiveStream] {
        let urlString = buildUrl(input: input, action: "get_live_streams")
        return try await fetch(urlString)
    }
    
    func getVodStreams(input: XtreamInput) async throws -> [XtreamChannelInfo.VodStream] {
        let urlString = buildUrl(input: input, action: "get_vod_streams")
        return try await fetch(urlString)
    }
    
    func getSeries(input: XtreamInput) async throws -> [XtreamChannelInfo.Series] {
        let urlString = buildUrl(input: input, action: "get_series")
        return try await fetch(urlString)
    }
    
    func getSeriesEpisodes(input: XtreamInput, seriesId: Int) async throws -> [XtreamChannelInfo.Episode] {
        let urlString = "\(input.basicUrl)/player_api.php?username=\(input.username)&password=\(input.password)&action=get_series_info&series_id=\(seriesId)"
        
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, _) = try await session.data(from: url)
        
        let container = try decoder.decode(XtreamChannelInfo.SeriesInfoContainer.self, from: data)
        let allEpisodes = container.episodes.flatMap { $0.value }
        
        return allEpisodes.sorted {
            if $0.season != $1.season {
                return $0.season < $1.season
            }
            return $0.episodeNum < $1.episodeNum
        }
    }
    
    // MARK: - Helpers
    
    private func buildUrl(input: XtreamInput, action: String) -> String {
        return "\(input.basicUrl)/player_api.php?username=\(input.username)&password=\(input.password)&action=\(action)"
    }
    
    private func fetch<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        
        return try decoder.decode(T.self, from: data)
    }
}
