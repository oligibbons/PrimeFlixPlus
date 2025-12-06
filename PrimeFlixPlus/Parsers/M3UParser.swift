import Foundation

class M3UParser {
    
    /// Parses M3U content in parallel to handle large (20k+) playlists instantly.
    static func parse(content: String, playlistUrl: String) async -> [ChannelStruct] {
        // 1. Split content into lines to prepare for parallel processing
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        if lines.isEmpty { return [] }
        
        // 2. Determine Chunk Size for Parallelism
        // For 20k items, ~2500 lines per chunk gives us ~8 parallel tasks, keeping all cores busy without overhead.
        let totalLines = lines.count
        let chunkSize = 2500
        
        return await withTaskGroup(of: [ChannelStruct].self) { group in
            var startIndex = 0
            
            while startIndex < totalLines {
                let endIndex = min(startIndex + chunkSize, totalLines)
                let chunk = Array(lines[startIndex..<endIndex])
                
                // Spawn a background task for this chunk
                group.addTask {
                    return parseChunk(lines: chunk, playlistUrl: playlistUrl)
                }
                
                startIndex = endIndex
            }
            
            // 3. Aggregate Results
            var allChannels: [ChannelStruct] = []
            // Pre-allocate to avoid resizing overhead
            allChannels.reserveCapacity(totalLines / 2)
            
            for await batch in group {
                allChannels.append(contentsOf: batch)
            }
            
            return allChannels
        }
    }
    
    // MARK: - Internal Chunk Logic
    
    /// Pure function running on background threads. No shared state.
    private static func parseChunk(lines: [String], playlistUrl: String) -> [ChannelStruct] {
        var channels: [ChannelStruct] = []
        var currentData: M3UData? = nil
        
        for line in lines {
            let l = line.trimmingCharacters(in: .whitespaces)
            
            if l.hasPrefix("#EXTINF:") {
                // Parse Metadata
                currentData = parseExtInf(line: l)
            } else if !l.hasPrefix("#") && currentData != nil {
                // Parse URL & Create Struct
                // This triggers TitleNormalizer (Regex) which is CPU intensive,
                // so running this in parallel chunks is a huge win.
                let channel = mapToStruct(data: currentData!, streamUrl: l, playlistUrl: playlistUrl)
                channels.append(channel)
                currentData = nil
            }
        }
        
        return channels
    }
    
    // MARK: - Helpers
    
    private static func parseExtInf(line: String) -> M3UData {
        // Format: #EXTINF:-1 tvg-id=".." group-title="..",Channel Name
        var title = "Unknown Channel"
        var metaPart = line
        
        if let lastCommaIndex = line.lastIndex(of: ",") {
            title = String(line[line.index(after: lastCommaIndex)...]).trimmingCharacters(in: .whitespaces)
            metaPart = String(line[..<lastCommaIndex])
        }
        
        let group = extractAttribute(line: metaPart, key: "group-title") ?? "Uncategorized"
        let logo = extractAttribute(line: metaPart, key: "tvg-logo")
        let tvgId = extractAttribute(line: metaPart, key: "tvg-id")
        
        return M3UData(title: title, url: "", group: group, logo: logo, tvgId: tvgId)
    }
    
    private static func extractAttribute(line: String, key: String) -> String? {
        // Optimization: Quick check before regex/scanning
        guard line.contains(key) else { return nil }
        
        // 1. Try Quoted: key="value"
        let keyQuote = "\(key)=\""
        if let range = line.range(of: keyQuote) {
            let substring = line[range.upperBound...]
            if let endRange = substring.firstIndex(of: "\"") {
                return String(substring[..<endRange])
            }
        }
        
        // 2. Try Unquoted: key=value
        let keySimple = "\(key)="
        if let range = line.range(of: keySimple) {
            let substring = line[range.upperBound...]
            // Stop at space or comma
            if let endRange = substring.rangeOfCharacter(from: CharacterSet(charactersIn: " ,")) {
                return String(substring[..<endRange.lowerBound])
            } else {
                return String(substring)
            }
        }
        
        return nil
    }
    
    private static func mapToStruct(data: M3UData, streamUrl: String, playlistUrl: String) -> ChannelStruct {
        let rawTitle = data.title ?? "Unknown Channel"
        let info = TitleNormalizer.parse(rawTitle: rawTitle) // CPU Heavy Step
        
        // Heuristic Type Detection
        var type: String
        let lowerUrl = streamUrl.lowercased()
        
        if lowerUrl.contains("/movie/") || lowerUrl.hasSuffix(".mp4") || lowerUrl.hasSuffix(".mkv") {
            type = "movie"
        } else if lowerUrl.contains("/series/") {
            type = "series"
        } else {
            type = "live"
        }
        
        // Extract Season/Episode info using the **Centralized Logic** in IntermediateModels
        let parsed = ChannelStruct.parseSeasonEpisode(from: rawTitle)
        let s = parsed.0
        let e = parsed.1
        
        // If we found S/E data, enforce "series" type even if URL looked like a movie
        if s > 0 || e > 0 {
            type = "series"
        }

        return ChannelStruct(
            url: streamUrl,
            playlistUrl: playlistUrl,
            title: info.normalizedTitle,
            group: data.group ?? "Uncategorized",
            cover: data.logo,
            type: type,
            canonicalTitle: rawTitle,
            quality: info.quality,
            seriesId: nil, // M3U files rarely provide a clean Series ID
            season: s,
            episode: e
        )
    }
}
