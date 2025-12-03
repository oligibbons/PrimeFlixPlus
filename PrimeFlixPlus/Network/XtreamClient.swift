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
            return "Server returned no data"
        case .parsingError:
            return "Data format not supported"
        }
    }
}

actor XtreamClient {
    private let session = UnsafeSession.shared
    private let decoder = JSONDecoder()
    
    // Trusted User-Agents
    private let userAgents = [
        "TiviMate/4.7.0 (Linux; Android 11)",
        "IPTVSmartersPro/1.1.1",
        "okhttp/3.12.1"
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
    
    // CRITICAL FIX: Return type is explicitly [XtreamCategory]
    func getVodCategories(input: XtreamInput) async throws -> [XtreamCategory] {
        // Some providers use get_vod_categories, result matches XtreamCategory structure
        let url = buildUrl(input: input, action: "get_vod_categories")
        return try await fetchWithRetry(url: url)
    }
    
    func getLiveStreams(input: XtreamInput, categoryId: String) async throws -> [XtreamChannelInfo.LiveStream] {
        let url = "\(input.basicUrl)/player_api.php?username=\(input.username)&password=\(input.password)&action=get_live_streams&category_id=\(categoryId)"
        return try await fetchWithRetry(url: url)
    }
    
    func getVodStreams(input: XtreamInput, categoryId: String) async throws -> [XtreamChannelInfo.VodStream] {
        let url = "\(input.basicUrl)/player_api.php?username=\(input.username)&password=\(input.password)&action=get_vod_streams&category_id=\(categoryId)"
        return try await fetchWithRetry(url: url)
    }
    
    func getSeriesEpisodes(input: XtreamInput, seriesId: Int) async throws -> [XtreamChannelInfo.Episode] {
        let url = "\(input.basicUrl)/player_api.php?username=\(input.username)&password=\(input.password)&action=get_series_info&series_id=\(seriesId)"
        do {
            let container: XtreamChannelInfo.SeriesInfoContainer = try await fetchWithRetry(url: url)
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
    
    private func fetchWithRetry<T: Decodable>(url: String) async throws -> T {
        var lastError: Error? = nil
        
        for (index, agent) in userAgents.enumerated() {
            do {
                if index > 0 {
                    let delay = UInt64(pow(2.0, Double(index))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
                return try await performRequest(urlString: url, userAgent: agent)
            } catch {
                lastError = error
                // Retry if Firewall/Limit error
                if let xErr = error as? XtreamError, case .invalidResponse(let code, _) = xErr {
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
        request.timeoutInterval = 120
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            if data.isEmpty { throw XtreamError.emptyData }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                if let str = String(data: data, encoding: .utf8), str == "[]" {
                    // Empty response handling if needed
                }
                throw XtreamError.parsingError
            }
        }
        
        var serverMsg: String? = nil
        if let body = String(data: data, encoding: .utf8) {
             let clean = body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
             serverMsg = String(clean.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        throw XtreamError.invalidResponse(statusCode: httpResponse.statusCode, message: serverMsg)
    }
}
