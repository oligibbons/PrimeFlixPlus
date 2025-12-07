import Foundation
import CoreData

struct ChannelStruct {
    let url: String
    let playlistUrl: String
    let title: String
    let group: String
    let cover: String?
    let type: String
    let canonicalTitle: String? // The RAW original title (Crucial for version matching)
    let quality: String?
    
    // NEW: Structured Series Metadata
    let seriesId: String?
    let season: Int
    let episode: Int
    
    // Generates a stable hash to detect if an item has CHANGED content (not just a duplicate)
    var contentHash: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(group)
        hasher.combine(seriesId)
        hasher.combine(season)
        hasher.combine(episode)
        // We do NOT include the URL here, because URL changes (e.g. token rotation) shouldn't reset the metadata
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
    
    // MARK: - Factory Methods (Aggressive Cleaning)
    
    static func from(_ item: XtreamChannelInfo.LiveStream, playlistUrl: String, input: XtreamInput, categoryMap: [String: String]) -> ChannelStruct {
        let rawName = item.name ?? ""
        // Critical: Parse raw name immediately to get clean title + quality tags
        let info = TitleNormalizer.parse(rawTitle: rawName)
        let catId = item.categoryId ?? ""
        let groupName = categoryMap[catId] ?? "Uncategorized"
        
        let url = "\(input.basicUrl)/live/\(input.username)/\(input.password)/\(item.streamId).m3u8"
        
        return ChannelStruct(
            url: url,
            playlistUrl: playlistUrl,
            title: info.normalizedTitle, // Clean: "BBC One"
            group: groupName,
            cover: item.streamIcon,
            type: "live",
            canonicalTitle: rawName,     // Raw: "UK | BBC One FHD"
            quality: info.quality,       // Parsed: "FHD"
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
        
        // Attempt to extract S/E from title if this VOD is accidentally an episode placed in Movies
        let (s, e) = parseSeasonEpisode(from: rawName)
        // If we found S/E, we force type to 'series_episode' to help aggregation later, or keep 'movie'
        let type = (s > 0 || e > 0) ? "series_episode" : "movie"
        
        return ChannelStruct(
            url: cleanUrl,
            playlistUrl: playlistUrl,
            title: info.normalizedTitle,
            group: groupName,
            cover: item.streamIcon,
            type: type,
            canonicalTitle: rawName,
            quality: info.quality,
            seriesId: nil, // VODs usually lack series_id in Xtream
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
            url: "series://\(item.seriesId)", // Virtual URL for the show container
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
        // Fallback: If title is null, construct one.
        let rawName = item.title ?? "Episode \(item.episodeNum)"
        
        // CLEANUP: Xtream often sends "S01 E01 - Title". We want just "Title" if possible, or clean "Episode X".
        // TitleNormalizer handles this, but we pass the raw string into canonicalTitle for matching.
        let info = TitleNormalizer.parse(rawTitle: rawName)
        
        // Construct Stream URL
        let streamUrl = "\(input.basicUrl)/series/\(input.username)/\(input.password)/\(item.id).\(item.containerExtension)"
        
        return ChannelStruct(
            url: streamUrl,
            playlistUrl: playlistUrl,
            title: info.normalizedTitle,
            group: "Episodes", // Episodes don't usually have their own group in Xtream
            cover: cover, // Inherit cover from Series
            type: "series_episode",
            canonicalTitle: rawName,
            quality: info.quality,
            seriesId: seriesId,
            season: item.season,
            episode: item.episodeNum
        )
    }
    
    // MARK: - Centralized Metadata Extraction (Public)
    
    /// Extracts S01E01 or Absolute Ordering (Episode 100) info from a string.
    static func parseSeasonEpisode(from title: String) -> (Int, Int) {
        let patterns = [
            // 1. Standard: S01E01, S1E1, s01 e01
            "(?i)S(\\d{1,2})\\s*E(\\d{1,2})",
            // 2. X Notation: 1x01
            "(?i)(\\d{1,2})x(\\d{1,2})",
            // 3. Verbose: Season 1 Episode 1
            "(?i)Season\\s*(\\d{1,2}).*Episode\\s*(\\d{1,3})",
            // 4. Absolute: Episode 100 (Treats as Season 1, Ep 100)
            "(?i)(?:^|\\s)(?:Ep|Episode)[\\.]?\\s*(\\d{1,4})"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
                
                let nsString = title as NSString
                
                // Case A, B, C (2 groups: Season/Episode)
                if match.numberOfRanges >= 3 {
                    let s = Int(nsString.substring(with: match.range(at: 1))) ?? 0
                    let e = Int(nsString.substring(with: match.range(at: 2))) ?? 0
                    if s > 0 || e > 0 { return (s, e) }
                }
                // Case D (1 group: Absolute Episode)
                else if match.numberOfRanges == 2 {
                    let e = Int(nsString.substring(with: match.range(at: 1))) ?? 0
                    return (1, e) // Default to Season 1 for absolute episode numbers
                }
            }
        }
        
        // Fallback: Check for loose number at end of string (Risky, but useful for Anime: "One Piece - 1050")
        // Refined Regex: " - 1050" or " [1050]"
        if let looseRegex = try? NSRegularExpression(pattern: "\\s[-\\[(]\\s*(\\d{1,4})(?:\\s|$|\\]|\\))"),
           let match = looseRegex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
            let valStr = (title as NSString).substring(with: match.range(at: 1))
            // Ensure it's not a year (19xx or 20xx)
            if let val = Int(valStr), (val < 1900 || val > 2100) {
                return (1, val)
            }
        }
        
        return (0, 0)
    }
}
