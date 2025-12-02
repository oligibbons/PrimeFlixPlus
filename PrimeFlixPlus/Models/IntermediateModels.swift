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
    
    static func from(_ item: XtreamChannelInfo.LiveStream, playlistUrl: String, input: XtreamInput) -> ChannelStruct {
        return ChannelStruct(
            url: "\(input.basicUrl)/live/\(input.username)/\(input.password)/\(item.streamId).ts",
            playlistUrl: playlistUrl,
            title: item.name ?? "",
            group: item.categoryId ?? "Uncategorized",
            cover: item.streamIcon,
            type: "live",
            canonicalTitle: item.name,
            quality: "SD"
        )
    }
    
    static func from(_ item: XtreamChannelInfo.VodStream, playlistUrl: String, input: XtreamInput) -> ChannelStruct {
        let info = TitleNormalizer.parse(rawTitle: item.name ?? "")
        return ChannelStruct(
            url: "\(input.basicUrl)/movie/\(input.username)/\(input.password)/\(item.streamId).\(item.containerExtension)",
            playlistUrl: playlistUrl,
            title: item.name ?? "",
            group: "Movies",
            cover: item.streamIcon,
            type: "movie",
            canonicalTitle: info.normalizedTitle,
            quality: info.quality
        )
    }
    
    static func from(_ item: XtreamChannelInfo.Series, playlistUrl: String) -> ChannelStruct {
        let info = TitleNormalizer.parse(rawTitle: item.name ?? "")
        return ChannelStruct(
            url: "series://\(item.seriesId)", // Placeholder URL for series parent
            playlistUrl: playlistUrl,
            title: item.name ?? "",
            group: "Series",
            cover: item.cover,
            type: "series",
            canonicalTitle: info.normalizedTitle,
            quality: nil
        )
    }
}
