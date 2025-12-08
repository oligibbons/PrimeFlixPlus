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
    
    // MARK: - Thread-Safe Conversion (NEW)
    
    /// Creates a struct from a Core Data Entity.
    /// Use this to pass data safely from a Background Context to the Main Actor.
    init(entity: Channel) {
        self.url = entity.url
        self.playlistUrl = entity.playlistUrl
        self.title = entity.title
        self.group = entity.group
        self.cover = entity.cover
        self.type = entity.type
        self.canonicalTitle = entity.canonicalTitle
        self.quality = entity.quality
        self.seriesId = entity.seriesId
        self.season = Int(entity.season)
        self.episode = Int(entity.episode)
    }
    
    // MARK: - Factory Methods (Aggressive Cleaning)
    
    // Internal Init for Factories
    init(url: String, playlistUrl: String, title: String, group: String, cover: String?, type: String, canonicalTitle: String?, quality: String?, seriesId: String?, season: Int, episode: Int) {
        self.url = url
        self.playlistUrl = playlistUrl
        self.title = title
        self.group = group
        self.cover = cover
        self.type = type
        self.canonicalTitle = canonicalTitle
        self.quality = quality
        self.seriesId = seriesId
        self.season = season
        self.episode = episode
    }
    
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
            quality: info.quality,
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
        
        let (s, e) = parseSeasonEpisode(from: rawName)
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
        let rawName = item.title ?? "Episode \(item.episodeNum)"
        let info = TitleNormalizer.parse(rawTitle: rawName)
        
        let streamUrl = "\(input.basicUrl)/series/\(input.username)/\(input.password)/\(item.id).\(item.containerExtension)"
        
        return ChannelStruct(
            url: streamUrl,
            playlistUrl: playlistUrl,
            title: info.normalizedTitle,
            group: "Episodes",
            cover: cover,
            type: "series_episode",
            canonicalTitle: rawName,
            quality: info.quality,
            seriesId: seriesId,
            season: item.season,
            episode: item.episodeNum
        )
    }
    
    static func parseSeasonEpisode(from title: String) -> (Int, Int) {
        let patterns = [
            "(?i)S(\\d{1,2})\\s*E(\\d{1,2})",
            "(?i)(\\d{1,2})x(\\d{1,2})",
            "(?i)Season\\s*(\\d{1,2}).*Episode\\s*(\\d{1,3})",
            "(?i)(?:^|\\s)(?:Ep|Episode)[\\.]?\\s*(\\d{1,4})"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
                
                let nsString = title as NSString
                if match.numberOfRanges >= 3 {
                    let s = Int(nsString.substring(with: match.range(at: 1))) ?? 0
                    let e = Int(nsString.substring(with: match.range(at: 2))) ?? 0
                    if s > 0 || e > 0 { return (s, e) }
                } else if match.numberOfRanges == 2 {
                    let e = Int(nsString.substring(with: match.range(at: 1))) ?? 0
                    return (1, e)
                }
            }
        }
        
        if let looseRegex = try? NSRegularExpression(pattern: "\\s[-\\[(]\\s*(\\d{1,4})(?:\\s|$|\\]|\\))"),
           let match = looseRegex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
            let valStr = (title as NSString).substring(with: match.range(at: 1))
            if let val = Int(valStr), (val < 1900 || val > 2100) {
                return (1, val)
            }
        }
        return (0, 0)
    }
}
