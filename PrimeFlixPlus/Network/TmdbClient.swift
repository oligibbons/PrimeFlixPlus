import Foundation

// MARK: - API Client
actor TmdbClient {
    private let apiKey: String = "YOUR_TMDB_API_KEY_HERE" // Move to Info.plist or Config in production
    private let baseUrl = "https://api.themoviedb.org/3"
    private let session = URLSession.shared
    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    
    // MARK: - Endpoints
    
    func searchMovie(query: String, year: String? = nil) async throws -> [TmdbMovieResult] {
        var params = [
            "api_key": apiKey,
            "query": query,
            "language": "en-US"
        ]
        if let year = year { params["year"] = year }
        
        let response: TmdbSearchResponse<TmdbMovieResult> = try await fetch("/search/movie", params: params)
        return response.results
    }
    
    func searchTv(query: String, year: String? = nil) async throws -> [TmdbTvResult] {
        var params = [
            "api_key": apiKey,
            "query": query,
            "language": "en-US"
        ]
        if let year = year { params["first_air_date_year"] = year }
        
        let response: TmdbSearchResponse<TmdbTvResult> = try await fetch("/search/tv", params: params)
        return response.results
    }
    
    func getMovieDetails(id: Int) async throws -> TmdbMovieDetails {
        let params = [
            "api_key": apiKey,
            "append_to_response": "credits",
            "language": "en-US"
        ]
        return try await fetch("/movie/\(id)", params: params)
    }
    
    // MARK: - Helper
    
    private func fetch<T: Decodable>(_ endpoint: String, params: [String: String]) async throws -> T {
        var urlComp = URLComponents(string: baseUrl + endpoint)!
        urlComp.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = urlComp.url else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return try jsonDecoder.decode(T.self, from: data)
    }
}

// MARK: - DTOs (Data Models)

struct TmdbSearchResponse<T: Decodable>: Decodable {
    let results: [T]
    let totalResults: Int
}

struct TmdbMovieResult: Decodable, Identifiable {
    let id: Int
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double
    let overview: String?
}

struct TmdbTvResult: Decodable, Identifiable {
    let id: Int
    let name: String
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double
    let overview: String?
    
    // Helper to match Movie interface
    var title: String { name }
}

struct TmdbMovieDetails: Decodable {
    let id: Int
    let title: String
    let overview: String?
    let genres: [TmdbGenre]
    let credits: TmdbCredits?
    let voteAverage: Double
    let posterPath: String?
    let backdropPath: String?
}

struct TmdbGenre: Decodable, Identifiable {
    let id: Int
    let name: String
}

struct TmdbCredits: Decodable {
    let cast: [TmdbCast]
}

struct TmdbCast: Decodable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
}
