import Foundation

/// Raw data representation of a single entry in an M3U playlist.
struct M3UData {
    let title: String?
    let url: String
    let group: String?
    let logo: String?
    let tvgId: String?
    let tvgName: String?
    let category: String?
    
    // Default values matching Kotlin implementation
    init(title: String? = nil,
         url: String,
         group: String? = nil,
         logo: String? = nil,
         tvgId: String? = nil,
         tvgName: String? = nil,
         category: String? = nil) {
        
        self.title = title
        self.url = url
        self.group = group
        self.logo = logo
        self.tvgId = tvgId
        self.tvgName = tvgName
        self.category = category
    }
}
