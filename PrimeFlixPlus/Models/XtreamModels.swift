import Foundation

// MARK: - Categories
/// Represents a category category from the Xtream API.
struct XtreamCategory: Codable, Identifiable {
    let categoryId: String
    let categoryName: String
    let parentId: Int
    
    // Conformance to Identifiable uses the API's unique ID
    var id: String { categoryId }
    
    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case parentId = "parent_id"
    }
    
    // Handle cases where parent_id might be missing in JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryId = try container.decode(String.self, forKey: .categoryId)
        categoryName = try container.decode(String.self, forKey: .categoryName)
        parentId = try container.decodeIfPresent(Int.self, forKey: .parentId) ?? 0
    }
}

// MARK: - Channel Info Namespace
/// Container for all Xtream Stream Information types
struct XtreamChannelInfo {
    
    /// Live TV Stream Metadata
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
    }
    
    /// Video On Demand (Movie) Metadata
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
        
        // Default values logic
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            streamId = try container.decode(Int.self, forKey: .streamId)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            streamIcon = try container.decodeIfPresent(String.self, forKey: .streamIcon)
            categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
            containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension) ?? "mp4"
            rating = try container.decodeIfPresent(String.self, forKey: .rating)
        }
    }
    
    /// Series Metadata
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
    }
    
    /// Container to handle the nested "episodes" map in JSON
    struct SeriesInfoContainer: Codable {
        let episodes: [String: [Episode]]
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            episodes = try container.decodeIfPresent([String: [Episode]].self, forKey: .episodes) ?? [:]
        }
    }
    
    /// Individual Episode Metadata
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
            // JSON IDs can sometimes be Ints or Strings, force to String
            if let idInt = try? container.decode(Int.self, forKey: .id) {
                id = String(idInt)
            } else {
                id = try container.decode(String.self, forKey: .id)
            }
            title = try container.decodeIfPresent(String.self, forKey: .title)
            containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension) ?? "mp4"
            season = try container.decodeIfPresent(Int.self, forKey: .season) ?? 0
            episodeNum = try container.decodeIfPresent(Int.self, forKey: .episodeNum) ?? 0
        }
    }
}
