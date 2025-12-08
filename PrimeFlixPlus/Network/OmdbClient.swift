import Foundation

// MARK: - OMDB Models

struct OmdbSeriesDetails: Codable {
    let title: String
    let year: String
    let rated: String?
    let released: String?
    let runtime: String?
    let genre: String?
    let director: String?
    let writer: String?
    let actors: String?
    let plot: String?
    let language: String?
    let country: String?
    let awards: String?
    let poster: String?
    let ratings: [OmdbRating]?
    let metascore: String?
    let imdbRating: String?
    let imdbVotes: String?
    let imdbID: String
    let totalSeasons: String?
    let response: String
    
    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case year = "Year"
        case rated = "Rated"
        case released = "Released"
        case runtime = "Runtime"
        case genre = "Genre"
        case director = "Director"
        case writer = "Writer"
        case actors = "Actors"
        case plot = "Plot"
        case language = "Language"
        case country = "Country"
        case awards = "Awards"
        case poster = "Poster"
        case ratings = "Ratings"
        case metascore = "Metascore"
        case imdbRating
        case imdbVotes
        case imdbID
        case totalSeasons
        case response = "Response"
    }
}

struct OmdbRating: Codable, Hashable {
    let source: String
    let value: String
    
    enum CodingKeys: String, CodingKey {
        case source = "Source"
        case value = "Value"
    }
}

struct OmdbSearchResult: Codable {
    let search: [OmdbSearchItem]?
    let totalResults: String?
    let response: String
    
    enum CodingKeys: String, CodingKey {
        case search = "Search"
        case totalResults
        case response = "Response"
    }
}

struct OmdbSearchItem: Codable {
    let title: String
    let year: String
    let imdbID: String
    let type: String
    let poster: String
    
    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case year = "Year"
        case imdbID
        case type = "Type"
        case poster = "Poster"
    }
}

// MARK: - Season / Episode Models (NEW)

struct OmdbSeasonResponse: Codable {
    let title: String?
    let season: String?
    let episodes: [OmdbSimpleEpisode]?
    let response: String
    
    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case season = "Season"
        case episodes = "Episodes"
        case response = "Response"
    }
}

struct OmdbSimpleEpisode: Codable {
    let title: String
    let released: String
    let episode: String
    let imdbRating: String
    let imdbID: String
    
    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case released = "Released"
        case episode = "Episode"
        case imdbRating
        case imdbID
    }
}

// Full details for a single episode (Used in Deep Fetch)
struct OmdbEpisodeDetails: Codable, Identifiable {
    let title: String
    let released: String?
    let episode: String?
    let season: String?
    let plot: String?
    let poster: String?
    let imdbID: String
    
    var id: String { imdbID }
    
    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case released = "Released"
        case episode = "Episode"
        case season = "Season"
        case plot = "Plot"
        case poster = "Poster"
        case imdbID
    }
}

// MARK: - Client

actor OmdbClient {
    private let apiKey = "fb1d6f8d"
    private let baseUrl = "https://www.omdbapi.com/"
    private let session = URLSession.shared
    
    // In-Memory Cache to protect API limits during a single session
    private var cache: [String: OmdbSeriesDetails] = [:]
    private var seasonCache: [String: [OmdbEpisodeDetails]] = [:] // Key: "imdbID_seasonNum"
    
    // MARK: - Public API
    
    /// Smart fetch: Checks memory cache -> Performs Search -> Fetches Details
    func getSeriesMetadata(title: String, year: String?) async -> OmdbSeriesDetails? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Check Memory Cache
        if let cached = cache[cleanTitle] {
            return cached
        }
        
        // 2. Search for ID
        guard let imdbID = await searchSeriesID(title: cleanTitle, year: year) else {
            return nil
        }
        
        // 3. Fetch Details using ID
        if let details = await fetchDetails(imdbID: imdbID) {
            cache[cleanTitle] = details // Save to cache
            return details
        }
        
        return nil
    }
    
    /// Fetches Season Details (including Plot/Image for every episode)
    /// Performs a "Deep Fetch" if necessary, as the standard Season API doesn't include Plot/Poster.
    func getSeasonDetails(imdbID: String, season: Int) async -> [OmdbEpisodeDetails]? {
        let cacheKey = "\(imdbID)_S\(season)"
        if let cached = seasonCache[cacheKey] { return cached }
        
        // 1. Fetch the Season List (Lightweight)
        // URL: ?i=tt123&Season=1
        let queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: imdbID),
            URLQueryItem(name: "Season", value: String(season))
        ]
        
        guard let url = buildUrl(items: queryItems) else { return nil }
        
        do {
            let (data, _) = try await session.data(from: url)
            let seasonResp = try JSONDecoder().decode(OmdbSeasonResponse.self, from: data)
            
            guard let simpleEpisodes = seasonResp.episodes, !simpleEpisodes.isEmpty else { return nil }
            
            // 2. Deep Fetch (Heavyweight)
            // Fetch full details for each episode in parallel to get Plot/Image
            let fullEpisodes = await withTaskGroup(of: OmdbEpisodeDetails?.self) { group -> [OmdbEpisodeDetails] in
                for ep in simpleEpisodes {
                    group.addTask {
                        return await self.fetchEpisodeDetails(imdbID: ep.imdbID)
                    }
                }
                
                var collected: [OmdbEpisodeDetails] = []
                for await result in group {
                    if let res = result { collected.append(res) }
                }
                // Re-sort by episode number
                return collected.sorted { (Int($0.episode ?? "0") ?? 0) < (Int($1.episode ?? "0") ?? 0) }
            }
            
            if !fullEpisodes.isEmpty {
                seasonCache[cacheKey] = fullEpisodes
                return fullEpisodes
            }
            
        } catch {
            print("⚠️ OMDB Season Fetch Error: \(error)")
        }
        return nil
    }
    
    // MARK: - Internal Steps
    
    private func fetchEpisodeDetails(imdbID: String) async -> OmdbEpisodeDetails? {
        let queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: imdbID),
            URLQueryItem(name: "plot", value: "short") // 'short' is usually enough for episodes
        ]
        
        guard let url = buildUrl(items: queryItems) else { return nil }
        
        do {
            let (data, _) = try await session.data(from: url)
            return try JSONDecoder().decode(OmdbEpisodeDetails.self, from: data)
        } catch {
            return nil
        }
    }
    
    private func searchSeriesID(title: String, year: String?) async -> String? {
        var queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "s", value: title),
            URLQueryItem(name: "type", value: "series")
        ]
        
        if let y = year, !y.isEmpty {
            queryItems.append(URLQueryItem(name: "y", value: y))
        }
        
        guard let url = buildUrl(items: queryItems) else { return nil }
        
        do {
            let (data, _) = try await session.data(from: url)
            let result = try JSONDecoder().decode(OmdbSearchResult.self, from: data)
            
            // Return first match
            return result.search?.first?.imdbID
        } catch {
            // Fallback: Try without year if it failed
            if year != nil {
                return await searchSeriesID(title: title, year: nil)
            }
            return nil
        }
    }
    
    private func fetchDetails(imdbID: String) async -> OmdbSeriesDetails? {
        let queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: imdbID),
            URLQueryItem(name: "plot", value: "full")
        ]
        
        guard let url = buildUrl(items: queryItems) else { return nil }
        
        do {
            let (data, _) = try await session.data(from: url)
            let details = try JSONDecoder().decode(OmdbSeriesDetails.self, from: data)
            return details
        } catch {
            print("⚠️ OMDB Details Error: \(error)")
            return nil
        }
    }
    
    private func buildUrl(items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: baseUrl)
        components?.queryItems = items
        return components?.url
    }
}
