import Foundation

struct ContentInfo {
    let rawTitle: String
    let normalizedTitle: String
    let quality: String      // "4K", "1080p", "SD"
    let language: String?    // "AR", "EN", "FR" etc.
    let year: String?
    
    // Helper to score quality for sorting (Higher is better)
    var qualityScore: Int {
        if quality.contains("4K") || quality.contains("UHD") { return 4000 }
        if quality.contains("1080") { return 1080 }
        if quality.contains("720") { return 720 }
        return 480
    }
}

enum TitleNormalizer {
    
    // Regex for common tags
    private static let yearPattern = "([.\\[(]?(19|20)\\d{2}[.\\])]?)"
    private static let resolutionPattern = "(4k|uhd|2160p|1080p|720p|480p|sd)"
    private static let codecPattern = "(h264|h265|hevc|x264|x265|aac|ac3|dts)"
    
    // Language Codes (Add more as needed)
    private static let languageMap: [String: String] = [
        "AR": "Arabic", "ARA": "Arabic",
        "EN": "English", "ENG": "English", "UK": "English", "US": "English",
        "FR": "French", "FRE": "French", "VF": "French",
        "ES": "Spanish", "SPA": "Spanish",
        "DE": "German", "GER": "German",
        "IT": "Italian", "ITA": "Italian",
        "RU": "Russian", "RUS": "Russian",
        "TR": "Turkish", "TUR": "Turkish",
        "MULTI": "Multi-Audio"
    ]
    
    static func parse(rawTitle: String) -> ContentInfo {
        var cleanTitle = rawTitle
        let lowerRaw = rawTitle.lowercased()
        
        // 1. Extract Year
        var year: String? = nil
        if let yearMatch = rawTitle.range(of: yearPattern, options: .regularExpression) {
            let yearRaw = String(rawTitle[yearMatch])
            year = yearRaw.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            // Remove year from title for cleaner display
            cleanTitle = cleanTitle.replacingOccurrences(of: yearRaw, with: "")
        }
        
        // 2. Identify Resolution
        let quality: String
        if lowerRaw.contains("4k") || lowerRaw.contains("uhd") || lowerRaw.contains("2160") { quality = "4K UHD" }
        else if lowerRaw.contains("1080") { quality = "1080p" }
        else if lowerRaw.contains("720") { quality = "720p" }
        else { quality = "SD" }
        
        // 3. Identify Language
        // We look for specific patterns like " Movie Name AR " or "[AR]" or "EN" at end
        var detectedLang: String? = nil
        
        // Tokenize by spaces and non-alphanumeric splitters
        let tokens = rawTitle.components(separatedBy: CharacterSet(charactersIn: " .-_[]()"))
        
        for token in tokens.reversed() { // search from back usually safer
            let up = token.uppercased()
            if let langName = languageMap[up] {
                detectedLang = langName
                break
            }
        }
        
        // 4. Cleanup Title
        // Remove Resolution/Codecs/Lang tags from the display title
        let patternsToRemove = [
            resolutionPattern,
            codecPattern,
            "\\b(" + languageMap.keys.joined(separator: "|") + ")\\b" // Remove lang codes
        ]
        
        for pattern in patternsToRemove {
            cleanTitle = cleanTitle.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Remove Year pattern again to be safe
        cleanTitle = cleanTitle.replacingOccurrences(of: yearPattern, with: "", options: .regularExpression)
        
        // Remove common garbage characters
        cleanTitle = cleanTitle.replacingOccurrences(of: "[._-]", with: " ", options: .regularExpression)
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) // Collapse spaces
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 5. Handling Series Prefixes (e.g. "US: The Office")
        if cleanTitle.contains(":") {
            let parts = cleanTitle.split(separator: ":")
            if let first = parts.first, first.count <= 3 {
                // Likely a prefix like "UK" or "US", strip it
                cleanTitle = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        
        return ContentInfo(
            rawTitle: rawTitle,
            normalizedTitle: cleanTitle,
            quality: quality,
            language: detectedLang,
            year: year
        )
    }
}
