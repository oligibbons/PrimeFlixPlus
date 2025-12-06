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
    
    // Helper to allow ingesting specific episodes if needed later
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
    
    // MARK: - Metadata Extraction Helper
    
    /// Extracts S01E01 style info from a string.
    /// Moved here from runtime logic to ingestion logic for performance.
    private static func parseSeasonEpisode(from title: String) -> (Int, Int) {
        let patterns = [
            "(?i)(S)(\\d+)\\s*(E)(\\d+)", // S01E01
            "(?i)(\\d+)x(\\d+)"           // 1x01
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
                
                let nsString = title as NSString
                // Adjust ranges based on pattern groups
                let sIndex = match.numberOfRanges == 5 ? 2 : 1
                let eIndex = match.numberOfRanges == 5 ? 4 : 2
                
                if let s = Int(nsString.substring(with: match.range(at: sIndex))),
                   let e = Int(nsString.substring(with: match.range(at: eIndex))) {
                    return (s, e)
                }
            }
        }
        return (0, 0)
    }
}
