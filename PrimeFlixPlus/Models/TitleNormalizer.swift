import Foundation

struct ContentInfo {
    let rawTitle: String
    let normalizedTitle: String
    let quality: String      // "4K", "1080p", "SD"
    let language: String?    // "Arabic", "English", "French" etc.
    let year: String?
    
    // Helper to score quality for sorting (Higher is better)
    // Used by DetailsViewModel to auto-pick the best version
    var qualityScore: Int {
        var score = 0
        
        // Base resolution score
        if quality.contains("4K") || quality.contains("UHD") { score += 4000 }
        else if quality.contains("1080") { score += 1080 }
        else if quality.contains("720") { score += 720 }
        else { score += 480 }
        
        // Bonus for specific keywords if needed (e.g. HDR)
        // This can be expanded later
        
        return score
    }
}

/// Utility to parse raw IPTV titles into clean metadata.
/// Extracts Year, Quality (4K/1080p), and Language tags.
enum TitleNormalizer {
    
    // --- Regex Patterns ---
    
    // Captures (1999) or [2020] or .2020.
    private static let yearPattern = "([.\\[(]?(19|20)\\d{2}[.\\])]?)"
    
    // Captures common resolutions
    private static let resolutionPattern = "\\b(4k|uhd|2160p|1080p|1080i|720p|720i|480p|576p|sd|hd)\\b"
    
    // Captures video codecs (to strip them out)
    private static let codecPattern = "\\b(h264|h265|hevc|x264|x265|av1|vp9|mpeg)\\b"
    
    // Captures audio tags (to strip them out)
    private static let audioPattern = "\\b(aac|ac3|dts|dd5\\.1|5\\.1|mp3|flac)\\b"
    
    // Captures common spacer characters
    private static let spacerPattern = "[._-]"
    
    // --- Language Mapping ---
    // Maps common IPTV codes to readable English names
    private static let languageMap: [String: String] = [
        "AR": "Arabic", "ARA": "Arabic", "KSA": "Arabic", "EGY": "Arabic",
        "EN": "English", "ENG": "English", "UK": "English", "US": "English", "USA": "English",
        "FR": "French", "FRE": "French", "VF": "French", "VOSTFR": "French",
        "ES": "Spanish", "SPA": "Spanish", "ESP": "Spanish", "LATINO": "Spanish",
        "DE": "German", "GER": "German", "DEU": "German",
        "IT": "Italian", "ITA": "Italian",
        "RU": "Russian", "RUS": "Russian",
        "TR": "Turkish", "TUR": "Turkish",
        "PT": "Portuguese", "POR": "Portuguese", "PT-BR": "Portuguese",
        "NL": "Dutch", "NED": "Dutch",
        "PL": "Polish", "POL": "Polish",
        "HI": "Hindi", "HIN": "Hindi",
        "MULTI": "Multi-Audio", "MULTISUB": "Multi-Audio"
    ]
    
    // --- Main Parsing Function ---
    
    static func parse(rawTitle: String) -> ContentInfo {
        var cleanTitle = rawTitle
        let lowerRaw = rawTitle.lowercased()
        
        // 1. Extract Year
        var year: String? = nil
        if let yearMatch = rawTitle.range(of: yearPattern, options: .regularExpression) {
            let yearRaw = String(rawTitle[yearMatch])
            // Extract strictly the digits 19xx or 20xx
            let digits = yearRaw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            
            // Validate year range broadly (e.g. 1900-2099)
            if digits.count == 4, let yInt = Int(digits), yInt > 1900 && yInt < 2100 {
                year = digits
                // Remove the year from the title string to clean it up
                cleanTitle = cleanTitle.replacingOccurrences(of: yearRaw, with: " ")
            }
        }
        
        // 2. Identify Resolution
        // We prioritize checking for 4K/UHD first as it overrides others
        let quality: String
        if lowerRaw.contains("4k") || lowerRaw.contains("uhd") || lowerRaw.contains("2160") {
            quality = "4K UHD"
        } else if lowerRaw.contains("1080") {
            quality = "1080p"
        } else if lowerRaw.contains("720") {
            quality = "720p"
        } else {
            quality = "SD"
        }
        
        // 3. Identify Language
        var detectedLang: String? = nil
        
        // We tokenize the string to find language codes.
        // We iterate backwards because language tags are usually suffixes (e.g. "Movie Name [EN]")
        let tokens = rawTitle.components(separatedBy: CharacterSet(charactersIn: " .-_[]()"))
        
        for token in tokens.reversed() {
            let up = token.uppercased()
            // Skip short numeric tokens (like season numbers) to avoid false positives if any
            if up.count < 2 { continue }
            
            if let langName = languageMap[up] {
                detectedLang = langName
                break // Stop at the first valid language tag found from the right
            }
        }
        
        // 4. Cleanup Title String
        // We want to remove all the metadata tags we found to leave just the "Name"
        
        // Remove Resolution tags
        cleanTitle = cleanTitle.replacingOccurrences(of: resolutionPattern, with: " ", options: [.regularExpression, .caseInsensitive])
        
        // Remove Codec tags
        cleanTitle = cleanTitle.replacingOccurrences(of: codecPattern, with: " ", options: [.regularExpression, .caseInsensitive])
        
        // Remove Audio tags
        cleanTitle = cleanTitle.replacingOccurrences(of: audioPattern, with: " ", options: [.regularExpression, .caseInsensitive])
        
        // Remove Language Codes (Aggressive removal of any known code)
        // This prevents "Movie Name EN" from showing as "Movie Name EN"
        let langKeys = languageMap.keys.joined(separator: "|")
        let langPattern = "\\b(" + langKeys + ")\\b"
        cleanTitle = cleanTitle.replacingOccurrences(of: langPattern, with: " ", options: [.regularExpression, .caseInsensitive])
        
        // Remove common brackets content if it looks like meta info (e.g. [X])
        // This is a heuristic; we accept some risk to get cleaner titles
        // cleanTitle = cleanTitle.replacingOccurrences(of: "\\[.*?\\]", with: " ", options: .regularExpression)
        
        // Remove prefixes (e.g. "US: ", "UK: ")
        if cleanTitle.contains(":") {
            let parts = cleanTitle.split(separator: ":")
            if let first = parts.first {
                // If the part before colon is short (<= 3 chars), treat it as a country code prefix
                if first.trimmingCharacters(in: .whitespaces).count <= 3 {
                    cleanTitle = parts.dropFirst().joined(separator: ":")
                }
            }
        }
        
        // Remove Season/Episode info for Movies if present (rare but happens)
        // For Series, we might want to keep it, but the UI usually handles it separately.
        // For now, we leave SxxExx in the title if it's not explicitly stripped,
        // but the parser handles Series separately anyway.
        
        // 5. Final Whitespace Cleanup
        // Replace dots, underscores, dashes with spaces
        cleanTitle = cleanTitle.replacingOccurrences(of: spacerPattern, with: " ", options: .regularExpression)
        // Collapse multiple spaces into one
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return ContentInfo(
            rawTitle: rawTitle,
            normalizedTitle: cleanTitle,
            quality: quality,
            language: detectedLang,
            year: year
        )
    }
    
    /// Generates a consistent key for grouping duplicates.
    /// This strips all non-alphanumeric chars and lowercases the string.
    /// Example: "The Matrix (1999)" -> "thematrix"
    static func generateGroupKey(_ normalizedTitle: String) -> String {
        return normalizedTitle
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
