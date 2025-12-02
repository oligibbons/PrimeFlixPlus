import Foundation

// Combined logic from StreamType.kt and DataSource.kt

/// Defines the specific type of content being streamed.
enum StreamType: String, Codable {
    case live
    case movie
    case series
}

/// Defines the source of the playlist data.
/// Replaces the Kotlin 'sealed class DataSource' with a robust Swift Enum.
enum DataSourceType: String, CaseIterable, Codable, Identifiable {
    case m3u
    case epg
    case xtream
    case emby
    case dropbox
    
    var id: String { self.rawValue }
    
    // Corresponds to the 'supported' flag in Kotlin
    var isSupported: Bool {
        switch self {
        case .m3u, .epg, .xtream:
            return true
        default:
            return false
        }
    }
    
    // Replaces the resource ID lookup.
    // In a real app, you would use NSLocalizedString here.
    var displayName: String {
        switch self {
        case .m3u: return "M3U Playlist"
        case .epg: return "EPG Source"
        case .xtream: return "Xtream Codes API"
        case .emby: return "Emby Media Server"
        case .dropbox: return "Dropbox"
        }
    }
    
    // Xtream specific sub-types constants
    struct XtreamConstants {
        static let typeLive = "live"
        static let typeVod = "vod"
        static let typeSeries = "series"
    }
}
