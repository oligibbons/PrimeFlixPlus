import Foundation

class M3UParser {
    
    // Optimized line-by-line parsing for memory efficiency
    static func parse(content: String, playlistUrl: String) async -> [ChannelStruct] {
        var channels: [ChannelStruct] = []
        // Pre-allocate to reduce array resizing overhead
        channels.reserveCapacity(1000)
        
        var currentData: M3UData? = nil
        
        // Use enumerateLines to avoid loading the entire string array into memory
        content.enumerateLines { line, _ in
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.isEmpty { return }
            
            if l.hasPrefix("#EXTINF:") {
                // Format: #EXTINF:-1 tvg-id=".." group-title="..",Channel Name
                
                // 1. Extract Title (Everything after the last comma)
                var title = "Unknown Channel"
                var metaPart = l
                
                if let lastCommaIndex = l.lastIndex(of: ",") {
                    title = String(l[l.index(after: lastCommaIndex)...]).trimmingCharacters(in: .whitespaces)
                    metaPart = String(l[..<lastCommaIndex])
                }
                
                // 2. Extract Attributes
                let group = extractAttribute(line: metaPart, key: "group-title") ?? "Uncategorized"
                let logo = extractAttribute(line: metaPart, key: "tvg-logo")
                let tvgId = extractAttribute(line: metaPart, key: "tvg-id")
                
                currentData = M3UData(title: title, url: "", group: group, logo: logo, tvgId: tvgId)
                
            } else if !l.hasPrefix("#") && currentData != nil {
                // This line is the URL
                let rawUrl = l
                if let data = currentData {
                    let channel = mapToStruct(data: data, streamUrl: rawUrl, playlistUrl: playlistUrl)
                    channels.append(channel)
                }
                currentData = nil
            }
        }
        
        return channels
    }
    
    private static func extractAttribute(line: String, key: String) -> String? {
        // 1. Try Quoted Value: key="value"
        let keyStr = "\(key)=\""
        if let range = line.range(of: keyStr) {
            let substring = line[range.upperBound...]
            if let endRange = substring.range(of: "\"") {
                return String(substring[..<endRange.lowerBound])
            }
        }
        
        // 2. Try Unquoted Value: key=value (Stop at space or comma)
        let keySimple = "\(key)="
        if let range = line.range(of: keySimple) {
            let substring = line[range.upperBound...]
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
        
        // Normalize Title using our optimized normalizer
        let info = TitleNormalizer.parse(rawTitle: rawTitle)
        
        // Heuristic Type Detection
        let type: String
        let lowerUrl = streamUrl.lowercased()
        
        if lowerUrl.contains("/movie/") || lowerUrl.hasSuffix(".mp4") || lowerUrl.hasSuffix(".mkv") {
            type = "movie"
        } else if lowerUrl.contains("/series/") {
            type = "series"
        } else {
            type = "live"
        }
        
        return ChannelStruct(
            url: streamUrl,
            playlistUrl: playlistUrl,
            title: info.normalizedTitle, // Display Clean Title
            group: data.group ?? "Uncategorized",
            cover: data.logo,
            type: type,
            canonicalTitle: rawTitle,    // Store Raw
            quality: info.quality
        )
    }
}
