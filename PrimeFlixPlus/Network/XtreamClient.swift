import Foundation

enum XtreamError: LocalizedError {
    case invalidResponse(statusCode: Int, message: String?)
    case emptyData
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let code, let msg):
            if let m = msg, !m.isEmpty {
                return "Error \(code): \(m)"
            }
            return "Server Error: \(code)"
        case .emptyData:
            return "Server returned no data"
        case .parsingError:
            return "Data format not supported"
        }
    }
}

actor XtreamClient {
    private let session = UnsafeSession.shared
    private let decoder = JSONDecoder()
    
    // Define User-Agents to cycle through if one gets blocked
    private let userAgents = [
        "IPTVSmartersPro/1.0",
        "VLC/3.0.16 LibVLC/3.0.16",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    ]
    
    // MARK: - API Calls
    
    func getLiveStreams(input: XtreamInput) async throws -> [XtreamChannelInfo.LiveStream] {
        return try await fetchWithRetry(url: buildUrl(input: input, action: "get_live_streams"))
    }
    
    func getVodStreams(input: XtreamInput) async throws -> [XtreamChannelInfo.VodStream] {
        return try await fetchWithRetry(url: buildUrl(input: input, action: "get_vod_streams"))
    }
    
    func getSeries(input: XtreamInput) async throws -> [XtreamChannelInfo.Series] {
        return try await fetchWithRetry(url: buildUrl(input: input, action: "get_series"))
    }
    
    func getSeriesEpisodes(input: XtreamInput, seriesId: Int) async throws -> [XtreamChannelInfo.Episode] {
        let urlString = "\(input.basicUrl)/player_api.php?username=\(input.username)&password=\(input.password)&action=get_series_info&series_id=\(seriesId)"
        
        do {
            let container: XtreamChannelInfo.SeriesInfoContainer = try await fetchWithRetry(url: urlString)
            return container.episodes.flatMap { $0.value }.sorted {
                if $0.season != $1.season { return $0.season < $1.season }
                return $0.episodeNum < $1.episodeNum
            }
        } catch {
            print("⚠️ Series Info Fetch Failed: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Internal Logic
    
    private func buildUrl(input: XtreamInput, action: String) -> String {
        return "\(input.basicUrl)/player_api.php?username=\(input.username)&password=\(input.password)&action=\(action)"
    }
    
    /// Smart wrapper that tries multiple User-Agents if the server rejects the request
    private func fetchWithRetry<T: Decodable>(url: String) async throws -> T {
        var lastError: Error? = nil
        
        for (index, agent) in userAgents.enumerated() {
            do {
                print("🔄 Attempt \(index + 1) with UA: \(agent)")
                return try await performRequest(urlString: url, userAgent: agent)
            } catch {
                lastError = error
                // If it's a server error (like 512, 403), continue to next Agent.
                // If it's a URL error (bad host), break immediately.
                if let xErr = error as? XtreamError, case .invalidResponse = xErr {
                    continue
                } else {
                    // Check for specific URLErrors that imply server rejection vs network failure
                    let nsErr = error as NSError
                    if nsErr.domain == NSURLErrorDomain && (nsErr.code == -1011 || nsErr.code == -1012) {
                        continue
                    }
                }
                print("❌ Fatal Network Error: \(error)")
                throw error
            }
        }
        
        throw lastError ?? URLError(.unknown)
    }
    
    private func performRequest<T: Decodable>(urlString: String, userAgent: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // Success Range
        if (200...299).contains(httpResponse.statusCode) {
            if data.isEmpty { throw XtreamError.emptyData }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                print("❌ JSON Decode Error: \(error)")
                if let str = String(data: data, encoding: .utf8) {
                    print("📄 Received: \(str.prefix(500))")
                }
                throw XtreamError.parsingError
            }
        }
        
        // Failure Handling
        print("❌ HTTP Error \(httpResponse.statusCode) for UA \(userAgent)")
        
        // Try to read server message
        var serverMsg: String? = nil
        if let body = String(data: data, encoding: .utf8) {
            let clean = body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            serverMsg = String(clean.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        throw XtreamError.invalidResponse(statusCode: httpResponse.statusCode, message: serverMsg)
    }
}
