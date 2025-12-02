import Foundation

struct ContentInfo {
    let rawTitle: String
    let normalizedTitle: String
    let quality: String
    let year: String?
}

/// Utility to parse raw IPTV titles into clean metadata.
/// Extracts Year, Quality (4K/1080p), and Language tags.
enum TitleNormalizer {
    
    // Regex patterns converted for Swift
    private static let tagsPattern = "([.\\[(]?(19|20)\\d{2}[.\\])]?)|(S\\d{1,2}E\\d{1,2})|(1080p|720p|480p|4k|uhd|hdr|h264|h265|hevc|x264|x265)|(multi|vostfr|vf|fr|en|eng|ita|spa|ger|ru|ar|it|es|de|af|be|nl|aus|sw|uk|nz|pt|tr|se|ic|no|fi|pl|ro|al|sl|bg|hu|lv|lt|sw|dk|gr|ca|lat|as|ko)|(\\[.*?\\])|(\\(.*?\\))"
    
    private static let langPattern = "(multi|vostfr|vf|fr|en|eng|ita|spa|ger|ru)"
    private static let spacerPattern = "[._-]"
    private static let yearPattern = "([.\\[(]?(19|20)\\d{2}[.\\])]?)"
    
    static func parse(rawTitle: String) -> ContentInfo {
        var cleanTitle = rawTitle
        
        // 1. Extract Year
        var year: String? = nil
        if let yearMatch = rawTitle.range(of: yearPattern, options: .regularExpression) {
            let yearRaw = String(rawTitle[yearMatch])
            year = yearRaw.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        }
        
        // 2. Identify Resolution
        let lowerRaw = rawTitle.lowercased()
        let res: String
        if lowerRaw.contains("4k") || lowerRaw.contains("uhd") {
            res = "4K"
        } else if lowerRaw.contains("1080") {
            res = "1080p"
        } else if lowerRaw.contains("720") {
            res = "720p"
        } else {
            res = "SD"
        }
        
        // 3. Identify Language
        var lang: String? = nil
        if let langRange = rawTitle.range(of: langPattern, options: [.regularExpression, .caseInsensitive]) {
            lang = String(rawTitle[langRange]).uppercased()
        }
        
        // Combined Quality Label
        let finalQuality = (lang != nil) ? "\(res) \(lang!)" : res
        
        // 4. Remove prefixes (e.g. "US: ")
        if cleanTitle.contains(":") {
            let parts = cleanTitle.split(separator: ":")
            // If prefix is short (like "US" or "UK"), strip it
            if parts.count > 1, let first = parts.first, first.count < 5 {
                cleanTitle = parts.dropFirst().joined(separator: ":")
            }
        }
        
        // 5. Regex Replace tags
        cleanTitle = cleanTitle.replacingOccurrences(of: tagsPattern, with: " ", options: [.regularExpression, .caseInsensitive])
        
        // 6. Cleanup spacers and whitespace
        cleanTitle = cleanTitle.replacingOccurrences(of: spacerPattern, with: " ", options: .regularExpression)
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse multiple spaces
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return ContentInfo(
            rawTitle: rawTitle,
            normalizedTitle: cleanTitle,
            quality: finalQuality,
            year: year
        )
    }
    
    static func generateGroupKey(_ normalizedTitle: String) -> String {
        return normalizedTitle
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
