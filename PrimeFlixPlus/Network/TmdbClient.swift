import Foundation

// MARK: - API Client
actor TmdbClient {
    
    // Auth
    private let accessToken = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI1ODZlMmViYWQ4ODVmZWUxZGEwMThhZjFiYjkxYWRhZiIsIm5iZiI6MTc2NDUxNTY3NS4yMDYsInN1YiI6IjY5MmM1ZjViOGEyMTVlNzllZTFlYzQ3MyIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.2nxr5v2nfVh0rfuq8LUOWfD0csKfB1VConOAiMRszRY"
    private let apiKey = "586e2ebad885fee1da018af1bb91adaf"
    private let baseUrl = "https://api.themoviedb.org/3"
    
    private let session = URLSession.shared
    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    
    // MARK: - Smart Search (The "Chillio" Logic)
    
    /// Orchestrates the search to find the best match.
    /// 1. Tries strict match (Title + Year).
    /// 2. If no TV results, retries WITHOUT year (fixes "The Bear S03 2024" issues).
    /// 3. Returns the top result.
    func findBestMatch(title: String, year: String?, type: String) async -> (id: Int, poster: String?, backdrop: String?)? {
        do {
            if type == "series" || type == "series_episode" {
                // 1. Try Strict Search (Title + Year)
                var results = try await searchTv(query: title, year: year)
                
                // 2. Fallback: If no results, try WITHOUT year
                // TV Shows often have years that don't match the file (e.g. Season Year vs Show Start Year)
                if results.isEmpty && year != nil {
                    print("⚠️ No TV match for '\(title)' + '\(year ?? "")'. Retrying without year...")
                    results = try await searchTv(query: title, year: nil)
                }
                
                if let best = results.first {
                    return (best.id, best.posterPath, best.backdropPath)
                }
            } else {
                // Movies usually match the release year correctly
                let results = try await searchMovie(query: title, year: year)
                
                // Minor fallback for movies just in case
                if results.isEmpty && year != nil {
                     let looseResults = try await searchMovie(query: title, year: nil)
                     if let best = looseResults.first { return (best.id, best.posterPath, best.backdropPath) }
                }
                
                if let best = results.first {
                    return (best.id, best.posterPath, best.backdropPath)
                }
            }
        } catch {
            print("⚠️ TMDB Search Failed for \(title): \(error)")
        }
        return nil
    }
    
    // MARK: - API Endpoints
    
    func searchMovie(query: String, year: String? = nil) async throws -> [TmdbMovieResult] {
        var params = ["query": query, "language": "en-US", "include_adult": "false"]
        if let year = year { params["primary_release_year"] = year }
        
        let response: TmdbSearchResponse<TmdbMovieResult> = try await fetch("/search/movie", params: params)
        return response.results
    }
    
    func searchTv(query: String, year: String? = nil) async throws -> [TmdbTvResult] {
        var params = ["query": query, "language": "en-US", "include_adult": "false"]
        if let year = year { params["first_air_date_year"] = year }
        
        let response: TmdbSearchResponse<TmdbTvResult> = try await fetch("/search/tv", params: params)
        return response.results
    }
    
    func getMovieDetails(id: Int) async throws -> TmdbDetails {
        let params = [
            "append_to_response": "credits,similar,release_dates,videos,images,external_ids",
            "language": "en-US",
            "include_image_language": "en,null"
        ]
        return try await fetch("/movie/\(id)", params: params)
    }
    
    func getTvDetails(id: Int) async throws -> TmdbDetails {
        let params = [
            "append_to_response": "aggregate_credits,similar,content_ratings,videos,images,external_ids",
            "language": "en-US",
            "include_image_language": "en,null"
        ]
        return try await fetch("/tv/\(id)", params: params)
    }
    
    func getTvSeason(tvId: Int, seasonNumber: Int) async throws -> TmdbSeasonDetails {
        let params = ["language": "en-US"]
        return try await fetch("/tv/\(tvId)/season/\(seasonNumber)", params: params)
    }
    
    func getTrending(type: String) async throws -> [TmdbTrendingItem] {
        let mediaType = (type == "series") ? "tv" : (type == "movie" ? "movie" : "all")
        let response: TmdbSearchResponse<TmdbTrendingItem> = try await fetch("/trending/\(mediaType)/week", params: [:])
        return response.results
    }
    
    // MARK: - Person Search (Actors/Directors)
    
    func searchPerson(query: String) async throws -> [TmdbPersonResult] {
        let params = [
            "query": query,
            "include_adult": "false",
            "language": "en-US",
            "page": "1"
        ]
        let response: TmdbSearchResponse<TmdbPersonResult> = try await fetch("/search/person", params: params)
        return response.results
    }
    
    func getPersonCredits(personId: Int) async throws -> TmdbPersonCredits {
        let params = ["language": "en-US"]
        return try await fetch("/person/\(personId)/combined_credits", params: params)
    }
    
    // MARK: - Core Fetch
    
    private func fetch<T: Decodable>(_ endpoint: String, params: [String: String]) async throws -> T {
        var urlComp = URLComponents(string: baseUrl + endpoint)!
        var queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        urlComp.queryItems = queryItems
        
        guard let url = urlComp.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return try jsonDecoder.decode(T.self, from: data)
    }
}

// MARK: - Models

struct TmdbSearchResponse<T: Decodable>: Decodable {
    let results: [T]
}

struct TmdbTrendingItem: Decodable, Identifiable {
    let id: Int
    let title: String?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    var displayTitle: String { title ?? name ?? "Unknown" }
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
}

struct TmdbDetails: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let genres: [TmdbGenre]?
    let voteAverage: Double?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let runtime: Int?
    let episodeRunTime: [Int]?
    
    let credits: TmdbCredits?
    let aggregateCredits: TmdbCredits?
    let similar: TmdbSearchResponse<TmdbMovieResult>?
    let videos: TmdbVideoResponse?
    let releaseDates: TmdbReleaseDates?
    let contentRatings: TmdbContentRatings?
    let images: TmdbImages?
    
    var displayTitle: String { title ?? name ?? "Unknown" }
    var displayDate: String? { releaseDate ?? firstAirDate }
    
    var logoPath: String? {
        images?.logos?.first(where: { $0.iso6391 == "en" })?.filePath ?? images?.logos?.first?.filePath
    }
    
    var certification: String? {
        if let releases = releaseDates?.results.first(where: { $0.iso31661 == "US" }) {
            return releases.releaseDates.first?.certification
        }
        if let ratings = contentRatings?.results.first(where: { $0.iso31661 == "US" }) {
            return ratings.rating
        }
        return nil
    }
}

struct TmdbGenre: Decodable, Identifiable {
    let id: Int
    let name: String
}

struct TmdbCredits: Decodable {
    let cast: [TmdbCast]?
    let crew: [TmdbCrew]?
}

struct TmdbCast: Decodable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
}

struct TmdbCrew: Decodable, Identifiable {
    let id: Int
    let name: String
    let job: String
}

struct TmdbVideoResponse: Decodable {
    let results: [TmdbVideo]
}

struct TmdbVideo: Decodable, Identifiable {
    let id: String
    let key: String
    let name: String
    let site: String
    let type: String
    var isTrailer: Bool { type == "Trailer" && site == "YouTube" }
}

struct TmdbReleaseDates: Decodable {
    let results: [TmdbIsoResult]
}
struct TmdbIsoResult: Decodable {
    let iso31661: String
    let releaseDates: [TmdbCertification]
}
struct TmdbCertification: Decodable {
    let certification: String
}

struct TmdbContentRatings: Decodable {
    let results: [TmdbTvRating]
}
struct TmdbTvRating: Decodable {
    let iso31661: String
    let rating: String
}

struct TmdbImages: Decodable {
    let logos: [TmdbImage]?
    let backdrops: [TmdbImage]?
}
struct TmdbImage: Decodable {
    let filePath: String
    let iso6391: String?
}

struct TmdbSeasonDetails: Decodable {
    let _id: String?
    let episodes: [TmdbEpisode]
}

struct TmdbEpisode: Decodable, Identifiable {
    let id: Int
    let name: String
    let episodeNumber: Int
    let seasonNumber: Int
    let overview: String?
    let stillPath: String?
    let voteAverage: Double?
}

struct TmdbSeason: Decodable, Identifiable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let episodeCount: Int
    let posterPath: String?
}

// MARK: - Person Models (New)

struct TmdbPersonResult: Decodable, Identifiable {
    let id: Int
    let name: String
    let profilePath: String?
    let knownForDepartment: String?
    
    var role: String { knownForDepartment ?? "Artist" }
}

struct TmdbPersonCredits: Decodable {
    let cast: [TmdbCreditItem]
    let crew: [TmdbCreditItem]
}

struct TmdbCreditItem: Decodable, Identifiable {
    let id: Int
    let title: String?
    let name: String?
    let posterPath: String?
    let job: String?
    let character: String?
    let popularity: Double?
    
    var displayTitle: String { title ?? name ?? "" }
}
