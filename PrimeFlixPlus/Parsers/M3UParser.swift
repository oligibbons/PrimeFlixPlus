import Foundation

class M3UParser {
    static func parse(content: String, playlistUrl: String) async -> [ChannelStruct] {
        var channels: [ChannelStruct] = []
        var currentData: M3UData? = nil // Fixed null -> nil
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.isEmpty { continue }
            
            if l.hasPrefix("#EXTINF:") {
                let titleParts = l.split(separator: ",")
                let title = titleParts.count > 1 ? String(titleParts.last!).trimmingCharacters(in: .whitespaces) : "Unknown Channel"
                let group = extractAttribute(line: l, key: "group-title") ?? "Uncategorized"
                let logo = extractAttribute(line: l, key: "tvg-logo")
                let tvgId = extractAttribute(line: l, key: "tvg-id")
                
                currentData = M3UData(title: title, url: "", group: group, logo: logo, tvgId: tvgId)
                
            } else if !l.hasPrefix("#") && currentData != nil {
                let rawUrl = l
                let data = currentData!
                let channel = mapToStruct(data: data, streamUrl: rawUrl, playlistUrl: playlistUrl)
                channels.append(channel)
                currentData = nil
            }
        }
        return channels
    }
    
    private static func extractAttribute(line: String, key: String) -> String? {
        let keyStr = "\(key)=\""
        guard let range = line.range(of: keyStr) else { return nil }
        let substring = line[range.upperBound...]
        if let endRange = substring.range(of: "\"") {
            return String(substring[..<endRange.lowerBound])
        }
        return nil
    }
    
    private static func mapToStruct(data: M3UData, streamUrl: String, playlistUrl: String) -> ChannelStruct {
        let rawTitle = data.title ?? "Unknown Channel"
        let info = TitleNormalizer.parse(rawTitle: rawTitle)
        
        let type: String
        let lowerUrl = streamUrl.lowercased()
        if lowerUrl.hasSuffix(".m3u8") || lowerUrl.contains("/live/") { type = "live" }
        else if lowerUrl.hasSuffix(".mp4") || lowerUrl.hasSuffix(".mkv") { type = "movie" }
        else { type = "live" }
        
        return ChannelStruct(
            url: streamUrl,
            playlistUrl: playlistUrl,
            title: rawTitle,
            group: data.group ?? "Uncategorized",
            cover: data.logo,
            type: type,
            canonicalTitle: info.normalizedTitle,
            quality: info.quality
        )
    }
}
