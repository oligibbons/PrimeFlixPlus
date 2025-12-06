import Foundation
import CoreData

struct ChannelStruct {
    let url: String
    let playlistUrl: String
    let title: String
    let group: String
    let cover: String?
    let type: String
    let canonicalTitle: String?
    let quality: String?
    
    // NEW: Structured Series Metadata
    let seriesId: String?
    let season: Int
    let episode: Int
    
    var contentHash: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(group)
        // Include metadata in hash so changes (e.g. corrected S/E) trigger an update
        hasher.combine(seriesId)
        hasher.combine(season)
        hasher.combine(episode)
        return hasher.finalize()
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "url": url,
            "playlistUrl": playlistUrl,
            "title": title,
            "group": group,
            "type": type,
            "addedAt": Date(),
            "isFavorite": false,
            
            // Map new fields for Core Data (using Int16 sizes)
            "season": Int16(season),
            "episode": Int16(episode)
        ]
        
        if let cover = cover { dict["cover"] = cover }
        if let canonical = canonicalTitle { dict["canonicalTitle"] = canonical }
        if let quality = quality { dict["quality"] = quality }
        if let sid = seriesId { dict["seriesId"] = sid }
        
        return dict
    }
    
    // MARK: - Factory Methods
    
    static func from(_ item: XtreamChannelInfo.LiveStream, playlistUrl: String, input: XtreamInput, categoryMap: [String: String]) -> ChannelStruct {
        let rawName = item.name ?? ""
        let info = TitleNormalizer.parse(rawTitle: rawName)
        let catId = item.categoryId ?? ""
        let groupName = categoryMap[catId] ?? "Uncategorized"
        
        let url = "\(input.basicUrl)/live/\(input.username)/\(input.password)/\(item.streamId).m3u8"
        
        return ChannelStruct(
            url: url,
            playlistUrl: playlistUrl,
            title: info.normalizedTitle,
            group: groupName,
            cover: item.streamIcon,
            type: "live",
            canonicalTitle: rawName,
            quality: "SD",
            seriesId: nil,
            season: 0,
            episode: 0
        )
    }
    
    static func from(_ item: XtreamChannelInfo.VodStream, playlistUrl: String, input: XtreamInput, categoryMap: [String: String]) -> ChannelStruct {
        let rawName = item.name ?? ""
        let info = TitleNormalizer.parse(rawTitle: rawName)
        let catId = item.categoryId ?? ""
        let groupName = categoryMap[catId] ?? "Movies"
        
        let ext = item.containerExtension
        let cleanUrl = "\(input.basicUrl)/movie/\(input.username)/\(input.password)/\(item.streamId).\(ext)"
        
        // Attempt to extract S/E from title if this VOD is actually an episode
        let (s, e) = parseSeasonEpisode(from: rawName)
        
        return ChannelStruct(
            url: cleanUrl,
            playlistUrl: playlistUrl,
            title: info.normalizedTitle,
            group: groupName,
            cover: item.streamIcon,
            type: "movie",
            canonicalTitle: rawName,
            quality: info.quality,
            seriesId: nil,
            season: s,
            episode: e
        )
    }
    
    static func from(_ item: XtreamChannelInfo.Series, playlistUrl: String, categoryMap: [String: String]) -> ChannelStruct {
        let rawName = item.name ?? ""
        let info = TitleNormalizer.parse(rawTitle: rawName)
        let catId = item.categoryId ?? ""
        let groupName = categoryMap[catId] ?? "Series"
        
        return ChannelStruct(
            url: "series://\(item.seriesId)",
            playlistUrl: playlistUrl,
            title: info.normalizedTitle,
            group: groupName,
            cover: item.cover,
            type: "series",
            canonicalTitle: rawName,
            quality: nil,
            seriesId: String(item.seriesId),
            season: 0,
            episode: 0
        )
    }
    
    static func from(_ item: XtreamChannelInfo.Episode, seriesId: String, playlistUrl: String, input: XtreamInput, cover: String?) -> ChannelStruct {
        let rawName = item.title ?? "Episode \(item.episodeNum)"
        let streamUrl = "\(input.basicUrl)/series/\(input.username)/\(input.password)/\(item.id).\(item.containerExtension)"
        
        return ChannelStruct(
            url: streamUrl,
            playlistUrl: playlistUrl,
            title: rawName,
            group: "Episodes",
            cover: cover,
            type: "series_episode",
            canonicalTitle: rawName,
            quality: nil,
            seriesId: seriesId,
            season: item.season,
            episode: item.episodeNum
        )
    }
    
    // MARK: - Centralized Metadata Extraction (Public)
    
    /// Extracts S01E01 or Absolute Ordering (Episode 100) info from a string.
    /// Now public so M3UParser can use it, ensuring consistency.
    static func parseSeasonEpisode(from title: String) -> (Int, Int) {
        let patterns = [
            // Standard: S01E01, S1E1
            "(?i)S(\\d{1,2})\\s*E(\\d{1,2})",
            // X Notation: 1x01
            "(?i)(\\d{1,2})x(\\d{1,2})",
            // Verbose: Season 1 Episode 1
            "(?i)Season\\s*(\\d{1,2}).*Episode\\s*(\\d{1,3})",
            // Absolute: Episode 100 (Treats as Season 1, Ep 100)
            "(?i)(?:^|\\s)(?:Ep|Episode)[\\.]?\\s*(\\d{1,4})"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
                
                let nsString = title as NSString
                
                // Case A: S01E01 (2 groups) - Checks for standard S/E formats with 2 capture groups
                if match.numberOfRanges >= 3 {
                    // This logic assumes Season is always Group 1 and Episode is Group 2 (relative to base match range)
                    let s = Int(nsString.substring(with: match.range(at: 1))) ?? 0
                    let e = Int(nsString.substring(with: match.range(at: 2))) ?? 0
                    if s > 0 || e > 0 { return (s, e) }
                }
                // Case B: Absolute Ordering (1 group)
                else if match.numberOfRanges == 2 {
                    let e = Int(nsString.substring(with: match.range(at: 1))) ?? 0
                    return (1, e) // Default to Season 1 for absolute episode numbers
                }
            }
        }
        
        // Fallback: Check for loose number at end of string (Risky, but useful for Anime: "One Piece - 1050")
        // Only if it doesn't look like a year (19xx or 20xx). This is a safe final check.
        if let looseRegex = try? NSRegularExpression(pattern: "\\s-\\s(\\d{1,4})(?:\\s|$|\\[|\\()"),
           let match = looseRegex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
            let valStr = (title as NSString).substring(with: match.range(at: 1))
            if let val = Int(valStr), (val < 1900 || val > 2100) {
                return (1, val)
            }
        }
        
        return (0, 0)
    }
}
