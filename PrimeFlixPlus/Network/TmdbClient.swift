import Foundation

// MARK: - API Client
actor TmdbClient {
    // REPLACE THIS WITH YOUR KEY if not injected via Info.plist or config
    private let apiKey: String = "YOUR_TMDB_API_KEY_HERE"
    private let baseUrl = "https://api.themoviedb.org/3"
    private let session = URLSession.shared
    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    
    // MARK: - Endpoints
    
    func searchMovie(query: String, year: String? = nil) async throws -> [TmdbMovieResult] {
        var params = ["api_key": apiKey, "query": query, "language": "en-US"]
        if let year = year { params["year"] = year }
        let response: TmdbSearchResponse<TmdbMovieResult> = try await fetch("/search/movie", params: params)
        return response.results
    }
    
    func searchTv(query: String, year: String? = nil) async throws -> [TmdbTvResult] {
        var params = ["api_key": apiKey, "query": query, "language": "en-US"]
        if let year = year { params["first_air_date_year"] = year }
        let response: TmdbSearchResponse<TmdbTvResult> = try await fetch("/search/tv", params: params)
        return response.results
    }
    
    func getMovieDetails(id: Int) async throws -> TmdbDetails {
        let params = ["api_key": apiKey, "append_to_response": "credits,similar", "language": "en-US"]
        return try await fetch("/movie/\(id)", params: params)
    }
    
    func getTvDetails(id: Int) async throws -> TmdbDetails {
        let params = ["api_key": apiKey, "append_to_response": "credits,similar", "language": "en-US"]
        return try await fetch("/tv/\(id)", params: params)
    }
    
    func getTvSeason(tvId: Int, seasonNumber: Int) async throws -> TmdbSeasonDetails {
        let params = ["api_key": apiKey, "language": "en-US"]
        return try await fetch("/tv/\(tvId)/season/\(seasonNumber)", params: params)
    }
    
    // MARK: - Helper
    
    private func fetch<T: Decodable>(_ endpoint: String, params: [String: String]) async throws -> T {
        var urlComp = URLComponents(string: baseUrl + endpoint)!
        urlComp.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = urlComp.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return try jsonDecoder.decode(T.self, from: data)
    }
}

// MARK: - Shared Models

struct TmdbSearchResponse<T: Decodable>: Decodable {
    let results: [T]
}

struct TmdbMovieResult: Decodable, Identifiable {
    let id: Int
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let overview: String?
}

struct TmdbTvResult: Decodable, Identifiable {
    let id: Int
    let name: String
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let overview: String?
    var title: String { name }
}

// Unified Detail Model
struct TmdbDetails: Decodable {
    let id: Int
    let title: String?
    let name: String? // For TV
    let overview: String?
    let genres: [TmdbGenre]?
    let credits: TmdbCredits?
    let voteAverage: Double?
    let posterPath: String?
    let backdropPath: String?
    let seasons: [TmdbSeason]? // Only for TV
    
    // NEW: Explicitly added properties for dates
    let releaseDate: String?
    let firstAirDate: String?
    
    var displayTitle: String { title ?? name ?? "Unknown" }
    
    // Helper to get the correct date regardless of content type
    var displayDate: String? { releaseDate ?? firstAirDate }
}

struct TmdbSeason: Decodable, Identifiable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let episodeCount: Int
}

struct TmdbSeasonDetails: Decodable {
    let id: String // Hash ID
    let episodes: [TmdbEpisode]
}

struct TmdbEpisode: Decodable, Identifiable {
    let id: Int
    let name: String
    let episodeNumber: Int
    let seasonNumber: Int
    let overview: String?
    let stillPath: String?
}

struct TmdbGenre: Decodable, Identifiable {
    let id: Int
    let name: String
}

struct TmdbCredits: Decodable {
    let cast: [TmdbCast]?
}

struct TmdbCast: Decodable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
}
