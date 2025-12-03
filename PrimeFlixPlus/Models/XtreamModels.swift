import Foundation

// MARK: - Helper Extension
private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: K) -> Int {
        if let intVal = try? decode(Int.self, forKey: key) { return intVal }
        if let strVal = try? decode(String.self, forKey: key), let intVal = Int(strVal) { return intVal }
        return 0
    }
    
    func decodeFlexibleString(forKey key: K) -> String? {
        if let strVal = try? decode(String.self, forKey: key) { return strVal }
        if let intVal = try? decode(Int.self, forKey: key) { return String(intVal) }
        return nil
    }
}

// MARK: - Categories
struct XtreamCategory: Codable, Identifiable {
    let categoryId: String
    let categoryName: String
    let parentId: Int
    
    var id: String { categoryId }
    
    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case parentId = "parent_id"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryId = container.decodeFlexibleString(forKey: .categoryId) ?? "0"
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName) ?? "Unknown"
        parentId = container.decodeFlexibleInt(forKey: .parentId)
    }
}

// MARK: - Channel Info Namespace
struct XtreamChannelInfo {
    
    struct LiveStream: Codable, Identifiable {
        let streamId: Int
        let name: String?
        let streamIcon: String?
        let categoryId: String?
        let epgChannelId: String?
        
        var id: Int { streamId }
        
        enum CodingKeys: String, CodingKey {
            case streamId = "stream_id"
            case name
            case streamIcon = "stream_icon"
            case categoryId = "category_id"
            case epgChannelId = "epg_channel_id"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            streamId = container.decodeFlexibleInt(forKey: .streamId)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            streamIcon = try container.decodeIfPresent(String.self, forKey: .streamIcon)
            categoryId = container.decodeFlexibleString(forKey: .categoryId)
            epgChannelId = container.decodeFlexibleString(forKey: .epgChannelId)
        }
    }
    
    struct VodStream: Codable, Identifiable {
        let streamId: Int
        let name: String?
        let streamIcon: String?
        let categoryId: String?
        let containerExtension: String
        let rating: String?
        
        var id: Int { streamId }
        
        enum CodingKeys: String, CodingKey {
            case streamId = "stream_id"
            case name
            case streamIcon = "stream_icon"
            case categoryId = "category_id"
            case containerExtension = "container_extension"
            case rating
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            streamId = container.decodeFlexibleInt(forKey: .streamId)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            streamIcon = try container.decodeIfPresent(String.self, forKey: .streamIcon)
            categoryId = container.decodeFlexibleString(forKey: .categoryId)
            containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension) ?? "mp4"
            rating = try container.decodeIfPresent(String.self, forKey: .rating)
        }
    }
    
    struct Series: Codable, Identifiable {
        let seriesId: Int
        let name: String?
        let cover: String?
        let categoryId: String?
        let rating: String?
        
        var id: Int { seriesId }
        
        enum CodingKeys: String, CodingKey {
            case seriesId = "series_id"
            case name
            case cover
            case categoryId = "category_id"
            case rating
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            seriesId = container.decodeFlexibleInt(forKey: .seriesId)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            cover = try container.decodeIfPresent(String.self, forKey: .cover)
            categoryId = container.decodeFlexibleString(forKey: .categoryId)
            rating = try container.decodeIfPresent(String.self, forKey: .rating)
        }
    }
    
    struct SeriesInfoContainer: Codable {
        let episodes: [String: [Episode]]
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            episodes = try container.decodeIfPresent([String: [Episode]].self, forKey: .episodes) ?? [:]
        }
    }
    
    struct Episode: Codable, Identifiable {
        let id: String
        let title: String?
        let containerExtension: String
        let season: Int
        let episodeNum: Int
        
        enum CodingKeys: String, CodingKey {
            case id
            case title
            case containerExtension = "container_extension"
            case season
            case episodeNum = "episode_num"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let intId = try? container.decode(Int.self, forKey: .id) {
                id = String(intId)
            } else {
                id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
            }
            title = try container.decodeIfPresent(String.self, forKey: .title)
            containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension) ?? "mp4"
            season = container.decodeFlexibleInt(forKey: .season)
            episodeNum = container.decodeFlexibleInt(forKey: .episodeNum)
        }
    }
}
