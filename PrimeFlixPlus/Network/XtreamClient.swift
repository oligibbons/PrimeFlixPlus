import Foundation

enum XtreamError: LocalizedError {
    case invalidResponse(statusCode: Int, message: String?)
    case emptyData
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let code, let msg):
            if let m = msg, !m.isEmpty { return "Error \(code): \(m)" }
            if code == 512 { return "Provider Error 512 (Firewall)" }
            if code == 513 { return "Provider Error 513 (Rate Limit)" }
            return "Server Error: \(code)"
        case .emptyData:
            return "Server returned empty data."
        case .parsingError:
            return "Data format not supported."
        }
    }
}

actor XtreamClient {
    private let session = UnsafeSession.shared
    private let decoder = JSONDecoder()
    
    // Trusted User-Agents (Rotated) + One Generic Fallback
    private let userAgents = [
        "TiviMate/4.7.0 (Linux; Android 11)",
        "IPTVSmartersPro/1.1.1",
        "okhttp/3.12.1",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ]
    
    // MARK: - Bulk API Calls
    
    func getLiveStreams(input: XtreamInput) async throws -> [XtreamChannelInfo.LiveStream] {
        return try await fetchWithRetry(url: buildUrl(input: input, action: "get_live_streams"))
    }
    
    func getVodStreams(input: XtreamInput) async throws -> [XtreamChannelInfo.VodStream] {
        return try await fetchWithRetry(url: buildUrl(input: input, action: "get_vod_streams"))
    }
    
    func getSeries(input: XtreamInput) async throws -> [XtreamChannelInfo.Series] {
        return try await fetchWithRetry(url: buildUrl(input: input, action: "get_series"))
    }
    
    // MARK: - Category-Based API Calls (Safe Mode)
    
    func getLiveCategories(input: XtreamInput) async throws -> [XtreamCategory] {
        return try await fetchWithRetry(url: buildUrl(input: input, action: "get_live_categories"))
    }
    
    func getVodCategories(input: XtreamInput) async throws -> [XtreamCategory] {
        let url = buildUrl(input: input, action: "get_vod_categories")
        return try await fetchWithRetry(url: url)
    }
    
    // MARK: - EPG & Deep Details
    
    /// Fetches Short EPG (TV Guide) for a specific live stream.
    /// - limit: Number of future programs to fetch (Default: 12).
    func getShortEPG(input: XtreamInput, streamId: Int, limit: Int = 12) async throws -> [XtreamEpgListing] {
        let url = "\(input.basicUrl)/player_api.php?username=\(input.username)&password=\(input.password)&action=get_short_epg&stream_id=\(streamId)&limit=\(limit)"
        
        do {
            let response: XtreamEpgResponse = try await fetchWithRetry(url: url)
            return response.epgListings
        } catch {
            // Xtream API Quirk: Returns "[]" (Empty Array) instead of empty object "{...}" when no EPG exists.
            // This causes a Decoding Error. We catch it here and treat it as "No Data".
            if let xErr = error as? XtreamError, case .parsingError = xErr {
                return []
            }
            // If decoding failed generally, it's also likely just empty/malformed EPG
            if error is DecodingError {
                return []
            }
            throw error
        }
    }
    
    func getSeriesEpisodes(input: XtreamInput, seriesId: String) async throws -> [XtreamChannelInfo.Episode] {
        let url = "\(input.basicUrl)/player_api.php?username=\(input.username)&password=\(input.password)&action=get_series_info&series_id=\(seriesId)"
        
        do {
            let container: XtreamChannelInfo.SeriesInfoContainer = try await fetchWithRetry(url: url)
            
            // Flatten Season Dictionary
            let allEpisodes = container.episodes.flatMap { (key, value) -> [XtreamChannelInfo.Episode] in
                return value
            }
            
            return allEpisodes.sorted {
                if $0.season != $1.season { return $0.season < $1.season }
                return $0.episodeNum < $1.episodeNum
            }
        } catch {
            print("⚠️ Series Info Fetch Failed for ID \(seriesId): \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Internal Logic
    
    private func buildUrl(input: XtreamInput, action: String) -> String {
        return "\(input.basicUrl)/player_api.php?username=\(input.username)&password=\(input.password)&action=\(action)"
    }
    
    private func fetchWithRetry<T: Decodable>(url: String) async throws -> T {
        var lastError: Error? = nil
        
        for (index, agent) in userAgents.enumerated() {
            do {
                if index > 0 {
                    // Exponential backoff
                    let delay = UInt64(pow(2.0, Double(index))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
                return try await performRequest(urlString: url, userAgent: agent)
            } catch {
                lastError = error
                
                // Retry specific network/server errors
                if let xErr = error as? XtreamError, case .invalidResponse(let code, _) = xErr {
                    // Don't retry 404s, but do retry 502/Gateway errors
                    if [403, 401, 512, 513, 502, 504, 520].contains(code) {
                        continue
                    }
                }
                
                let nsErr = error as NSError
                if nsErr.domain == NSURLErrorDomain && (nsErr.code == -1011 || nsErr.code == -1012 || nsErr.code == -1001) {
                    continue
                }
                if nsErr.domain == NSURLErrorDomain && nsErr.code == -1003 { throw error }
            }
        }
        throw lastError ?? URLError(.unknown)
    }
    
    private func performRequest<T: Decodable>(urlString: String, userAgent: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("close", forHTTPHeaderField: "Connection")
        
        // FIX: Increased timeout for large library fetching
        request.timeoutInterval = 180
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            if data.isEmpty { throw XtreamError.emptyData }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                // Handling empty array/object mismatch
                if let str = String(data: data, encoding: .utf8), str == "[]" {
                    // If T is expected to be an array, this is fine, but if T is a struct, it fails.
                    // We attempt to decode empty object for struct expectations.
                    if let emptyObj = "{}".data(using: .utf8), let fallback = try? decoder.decode(T.self, from: emptyObj) {
                        return fallback
                    }
                }
                // Don't print decoding error for EPG, it's expected often
                if !(T.self is XtreamEpgResponse.Type) {
                    print("❌ Decoding Error for URL: \(urlString) - \(error)")
                }
                throw XtreamError.parsingError
            }
        }
        
        // Error Message Extraction (Handling HTML bodies)
        var serverMsg: String? = nil
        if let body = String(data: data, encoding: .utf8) {
             let clean = body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
             serverMsg = String(clean.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        throw XtreamError.invalidResponse(statusCode: httpResponse.statusCode, message: serverMsg)
    }
}
