import Foundation
import CoreData

/// A thread-safe struct to hold channel data before it is saved to Core Data.
struct ChannelStruct {
    let url: String
    let playlistUrl: String
    let title: String
    let group: String
    let cover: String?
    let type: String
    let canonicalTitle: String?
    let quality: String?
    
    // MARK: - High Performance Helpers
    
    /// Generates a hash to quickly compare if the content has changed without loading the object.
    var contentHash: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(group)
        return hasher.finalize()
    }
    
    /// Converts struct to a Dictionary for NSBatchInsertRequest (Direct SQLite Write).
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "url": url,
            "playlistUrl": playlistUrl,
            "title": title,
            "group": group,
            "type": type,
            "addedAt": Date(),
            "isFavorite": false
        ]
        
        if let cover = cover { dict["cover"] = cover }
        if let canonical = canonicalTitle { dict["canonicalTitle"] = canonical }
        if let quality = quality { dict["quality"] = quality }
        
        return dict
    }
    
    // MARK: - Sanitization Helpers (The "Nuclear" Logic)
    
    private static func sanitizeCredentials(_ text: String) -> String {
        return text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
    }
    
    // MARK: - Factory Methods
    
    static func from(_ item: XtreamChannelInfo.LiveStream, playlistUrl: String, input: XtreamInput, categoryMap: [String: String]) -> ChannelStruct {
        let rawName = item.name ?? ""
        let info = TitleNormalizer.parse(rawTitle: rawName)
        let catId = item.categoryId ?? ""
        let groupName = categoryMap[catId] ?? "Uncategorized"
        
        // NUCLEAR FIX: Live TV
        // 1. Force .m3u8 extension (HLS) instead of .ts (MPEG-TS) for stability on tvOS.
        // 2. Percent-encode credentials to prevent URL breaks.
        let safeUser = sanitizeCredentials(input.username)
        let safePass = sanitizeCredentials(input.password)
        
        // Construct HLS URL
        let cleanUrl = "\(input.basicUrl)/live/\(safeUser)/\(safePass)/\(item.streamId).m3u8"
        
        return ChannelStruct(
            url: cleanUrl,
            playlistUrl: playlistUrl,
            title: info.normalizedTitle,
            group: groupName,
            cover: item.streamIcon,
            type: "live",
            canonicalTitle: rawName,
            quality: "SD"
        )
    }
    
    static func from(_ item: XtreamChannelInfo.VodStream, playlistUrl: String, input: XtreamInput, categoryMap: [String: String]) -> ChannelStruct {
        let rawName = item.name ?? ""
        let info = TitleNormalizer.parse(rawTitle: rawName)
        let catId = item.categoryId ?? ""
        let groupName = categoryMap[catId] ?? "Movies"
        
        // NUCLEAR FIX: VOD
        // 1. Detect unsupported containers (.mkv, .avi) and swap to .mp4 to request transcoding/remuxing.
        // 2. Encode credentials.
        let safeUser = sanitizeCredentials(input.username)
        let safePass = sanitizeCredentials(input.password)
        
        var ext = item.containerExtension.lowercased()
        if ext == "mkv" || ext == "avi" {
            ext = "mp4"
        }
        
        let cleanUrl = "\(input.basicUrl)/movie/\(safeUser)/\(safePass)/\(item.streamId).\(ext)"
        
        return ChannelStruct(
            url: cleanUrl,
            playlistUrl: playlistUrl,
            title: info.normalizedTitle,
            group: groupName,
            cover: item.streamIcon,
            type: "movie",
            canonicalTitle: rawName,
            quality: info.quality
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
            quality: nil
        )
    }
}
