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
    
    // MARK: - Routing Logic (The "Chillio" Fix)
    
    /// Constructs a safe playback URL.
    /// If the format is supported (mp4, m4v), it plays directly.
    /// If unsupported (mkv, avi), it routes through the HLS endpoint to force server-side remuxing.
    private static func buildStreamUrl(input: XtreamInput, streamId: Int, extension ext: String) -> String {
        // CLEAN CREDENTIALS: Do NOT percent encode here.
        // We trust the raw strings unless they contain extremely unsafe chars.
        // Percent encoding often breaks servers that expect raw auth in paths.
        let user = input.username
        let pass = input.password
        
        let fileExt = ext.lowercased()
        
        // LOGIC:
        // 1. If it's MP4/M4V, AVPlayer handles it natively. Use standard VOD endpoint.
        // 2. If it's MKV/AVI/Other, AVPlayer fails. We force HLS (.m3u8) via the /live/ endpoint.
        //    Xtream servers usually remux VOD to HLS when accessed this way.
        
        if fileExt == "mp4" || fileExt == "m4v" || fileExt == "mov" {
            // Direct Play
            return "\(input.basicUrl)/movie/\(user)/\(pass)/\(streamId).\(ext)"
        } else {
            // Force HLS Remux
            // Note: We use /live/ structure because that's the HLS gateway for most Xtream servers
            return "\(input.basicUrl)/live/\(user)/\(pass)/\(streamId).m3u8"
        }
    }
    
    // MARK: - Factory Methods
    
    static func from(_ item: XtreamChannelInfo.LiveStream, playlistUrl: String, input: XtreamInput, categoryMap: [String: String]) -> ChannelStruct {
        let rawName = item.name ?? ""
        let info = TitleNormalizer.parse(rawTitle: rawName)
        let catId = item.categoryId ?? ""
        let groupName = categoryMap[catId] ?? "Uncategorized"
        
        // Live is always HLS
        let url = "\(input.basicUrl)/live/\(input.username)/\(input.password)/\(item.streamId).m3u8"
        
        return ChannelStruct(
            url: url,
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
        
        // Apply Smart Routing
        let cleanUrl = buildStreamUrl(input: input, streamId: item.streamId, extension: item.containerExtension)
        
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
