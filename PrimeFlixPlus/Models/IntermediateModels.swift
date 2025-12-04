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
    
    /// Converts this struct into a live database object
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
    
    // MARK: - Factory Methods
    
    static func from(_ item: XtreamChannelInfo.LiveStream, playlistUrl: String, input: XtreamInput, categoryMap: [String: String]) -> ChannelStruct {
        let rawName = item.name ?? ""
        let info = TitleNormalizer.parse(rawTitle: rawName)
        
        // Resolve Category Name from ID, default to "Uncategorized" if missing
        let catId = item.categoryId ?? ""
        let groupName = categoryMap[catId] ?? "Uncategorized"
        
        return ChannelStruct(
            url: "\(input.basicUrl)/live/\(input.username)/\(input.password)/\(item.streamId).ts",
            playlistUrl: playlistUrl,
            title: info.normalizedTitle,
            group: groupName, // SAVES REAL NAME NOW
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
