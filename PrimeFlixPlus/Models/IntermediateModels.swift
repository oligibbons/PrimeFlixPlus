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
    /// We combine Title and Group, as these are the main metadata fields that might update.
    var contentHash: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(group)
        // We generally ignore cover/quality updates for pure sync speed,
        // unless you strictly need them updated every time.
        return hasher.finalize()
    }
    
    /// Converts struct to a Dictionary for NSBatchInsertRequest (Direct SQLite Write).
    /// This bypasses the overhead of creating NSManagedObjects.
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "url": url,
            "playlistUrl": playlistUrl,
            "title": title,
            "group": group,
            "type": type,
            "addedAt": Date(),
            "isFavorite": false // Default for new items
        ]
        
        if let cover = cover { dict["cover"] = cover }
        if let canonical = canonicalTitle { dict["canonicalTitle"] = canonical }
        if let quality = quality { dict["quality"] = quality }
        
        return dict
    }
    
    // MARK: - Legacy Factory Methods (Preserved)
    
    func toManagedObject(context: NSManagedObjectContext) -> Channel {
        return Channel(
            context: context,
            playlistUrl: playlistUrl,
            url: url,
            title: title,
            group: group,
            cover: cover,
            type: type,
            canonicalTitle: canonicalTitle,
            quality: quality
        )
    }
    
    static func from(_ item: XtreamChannelInfo.LiveStream, playlistUrl: String, input: XtreamInput, categoryMap: [String: String]) -> ChannelStruct {
        let rawName = item.name ?? ""
        let info = TitleNormalizer.parse(rawTitle: rawName)
        let catId = item.categoryId ?? ""
        let groupName = categoryMap[catId] ?? "Uncategorized"
        
        return ChannelStruct(
            url: "\(input.basicUrl)/live/\(input.username)/\(input.password)/\(item.streamId).ts",
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
        
        return ChannelStruct(
            url: "\(input.basicUrl)/movie/\(input.username)/\(input.password)/\(item.streamId).\(item.containerExtension)",
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
