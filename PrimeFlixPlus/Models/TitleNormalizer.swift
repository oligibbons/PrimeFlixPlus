import Foundation

struct ContentInfo {
    let rawTitle: String
    let normalizedTitle: String
    let quality: String      // "4K UHD", "1080p", "SD"
    let language: String?    // "Arabic", "English", "French" etc.
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
    
    // Language Codes (Expanded list)
    private static let languageMap: [String: String] = [
        "AR": "Arabic", "ARA": "Arabic", "KSA": "Arabic",
        "EN": "English", "ENG": "English", "UK": "English", "US": "English",
        "FR": "French", "FRE": "French", "VF": "French", "VOSTFR": "French",
        "ES": "Spanish", "SPA": "Spanish",
        "DE": "German", "GER": "German",
        "IT": "Italian", "ITA": "Italian",
        "RU": "Russian", "RUS": "Russian",
        "TR": "Turkish", "TUR": "Turkish",
        "PT": "Portuguese", "POR": "Portuguese",
        "NL": "Dutch",
        "PL": "Polish",
        "MULTI": "Multi-Audio"
    ]
    
    static func parse(rawTitle: String) -> ContentInfo {
        var cleanTitle = rawTitle
        let lowerRaw = rawTitle.lowercased()
        
        // 1. Extract Year
        var year: String? = nil
        if let yearMatch = rawTitle.range(of: yearPattern, options: .regularExpression) {
            let yearRaw = String(rawTitle[yearMatch])
            // Extract just digits
            let digits = yearRaw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if digits.count == 4 {
                year = digits
                // Remove year from title for cleaner display
                cleanTitle = cleanTitle.replacingOccurrences(of: yearRaw, with: "")
            }
        }
        
        // 2. Identify Resolution
        let quality: String
        if lowerRaw.contains("4k") || lowerRaw.contains("uhd") || lowerRaw.contains("2160") { quality = "4K UHD" }
        else if lowerRaw.contains("1080") { quality = "1080p" }
        else if lowerRaw.contains("720") { quality = "720p" }
        else { quality = "SD" }
        
        // 3. Identify Language
        // We look for tokens that match our language map
        var detectedLang: String? = nil
        
        // Tokenize by spaces and common separators
        let tokens = rawTitle.components(separatedBy: CharacterSet(charactersIn: " .-_[]()"))
        
        // Search from the end backwards (language tags are usually suffixes)
        for token in tokens.reversed() {
            let up = token.uppercased()
            if let langName = languageMap[up] {
                detectedLang = langName
                break
            }
        }
        
        // 4. Cleanup Title
        // Remove Resolution/Codecs tags from the display title
        let patternsToRemove = [
            resolutionPattern,
            codecPattern
        ]
        
        for pattern in patternsToRemove {
            cleanTitle = cleanTitle.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Remove Language Codes from title if found
        if let lang = detectedLang {
            // Try to remove the specific code we found?
            // A simpler approach for now is removing known codes that appear as standalone tokens
            let codePattern = "\\b(" + languageMap.keys.joined(separator: "|") + ")\\b"
            cleanTitle = cleanTitle.replacingOccurrences(of: codePattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Remove Year pattern again to be safe if it wasn't caught earlier
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
    
    /// Generates a consistent key for grouping duplicates
    static func generateGroupKey(_ normalizedTitle: String) -> String {
        return normalizedTitle
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
