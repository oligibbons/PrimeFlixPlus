import Foundation

// Wrapper to allow NSCache to store Structs (which are value types)
class ContentInfoWrapper: NSObject {
    let info: ContentInfo
    init(_ info: ContentInfo) { self.info = info }
}

struct ContentInfo {
    let rawTitle: String
    let normalizedTitle: String // Clean for Grouping (e.g. "Severance")
    let displayTitle: String    // UI Friendly (e.g. "Severance")
    
    // Metadata extracted from tags
    let quality: String      // "4K", "1080p", "SD"
    let language: String?    // "English", "French"
    let year: String?
    let season: Int
    let episode: Int
    let isSeries: Bool
    
    // Helper to score quality for sorting (Higher is better)
    var qualityScore: Int {
        var score = 0
        let q = quality.lowercased()
        
        // Resolution weight
        if q.contains("8k") { score += 8000 }
        else if q.contains("4k") || q.contains("uhd") { score += 4000 }
        else if q.contains("1080") { score += 1080 }
        else if q.contains("720") { score += 720 }
        else if q.contains("480") || q.contains("sd") { score += 480 }
        
        // Bonus for Audio/Codec features
        if q.contains("hevc") || q.contains("x265") { score += 100 }
        if q.contains("10bit") { score += 50 }
        if q.contains("5.1") || q.contains("atmos") { score += 50 }
        
        return score
    }
}

/// A "Scene Release" aware parser.
/// Strategy: Find the "Anchor" (Year or SxxExx), discard the right side, clean the left side.
enum TitleNormalizer {
    
    // MARK: - Thread-Safe Caching
    private static let cache = NSCache<NSString, ContentInfoWrapper>()
    
    // MARK: - Anchors
    // Finds "2021" or "1999" surrounded by delimiters
    private static let yearAnchorRegex = try! NSRegularExpression(
        pattern: "[\\.\\s\\(\\[\\-](19\\d{2}|20\\d{2})[\\.\\s\\)\\]\\-]",
        options: []
    )
    
    // Finds "S01E01", "Season 1", "1x01"
    private static let seriesAnchorRegex = try! NSRegularExpression(
        pattern: "(?i)(?:s|season)[\\.\\s]?(\\d{1,2})[\\.\\s]?(?:e|x|episode)[\\.\\s]?(\\d{1,3})",
        options: []
    )
    
    // MARK: - Metadata Detectors
    private static let prefixRegex = try! NSRegularExpression(
        pattern: "^(?:[A-Z0-9]{2,4}\\s*[|:-]\\s*)+",
        options: []
    )
    
    // Aggressive Tag Stripping List
    // These are removed from the END of the normalized title to merge "Severance Fr" and "Severance"
    private static let tagsToRemove: Set<String> = [
        // Languages
        "FR", "FRE", "VF", "VOSTFR", "FRENCH",
        "EN", "ENG", "ENGLISH", "VO",
        "DE", "GER", "DEUTSCH", "GERMAN",
        "ES", "SPA", "ESP", "SPANISH", "LATINO",
        "IT", "ITA", "ITALIAN",
        "RU", "RUS", "RUSSIAN",
        "TR", "TUR", "TURKISH",
        "PT", "POR", "PORTUGUESE", "BR",
        "PL", "POL", "POLISH",
        "NL", "DUTCH",
        "SUB", "DUB", "MULTI",
        
        // Quality / Format
        "4K", "UHD", "2160P", "1080P", "720P", "SD", "FHD", "HD",
        "HEVC", "H265", "H264", "X264", "X265", "HDR", "10BIT",
        "BLURAY", "WEB-DL", "WEBRIP", "DV", "ATMOS", "REMUX",
        
        // Providers / Junk
        "AMZN", "NFLX", "DISNEY", "HULU", "APPLE", "TVP", "HBO", "MAX"
    ]
    
    private static let languageMap: [String: String] = [
        "AR": "Arabic", "ARA": "Arabic", "KSA": "Arabic",
        "EN": "English", "ENG": "English", "UK": "English", "US": "English",
        "FR": "French", "FRE": "French", "VF": "French", "VOSTFR": "French",
        "ES": "Spanish", "SPA": "Spanish", "ESP": "Spanish", "LATINO": "Spanish",
        "DE": "German", "GER": "German", "DEU": "German",
        "IT": "Italian", "ITA": "Italian",
        "RU": "Russian", "RUS": "Russian",
        "TR": "Turkish", "TUR": "Turkish",
        "PT": "Portuguese", "POR": "Portuguese", "BR": "Portuguese",
        "NL": "Dutch", "NED": "Dutch",
        "PL": "Polish", "POL": "Polish",
        "HI": "Hindi", "HIN": "Hindi",
        "MULTI": "Multi-Audio", "SUB": "Subbed"
    ]
    
    // MARK: - Main Parser
    
    static func parse(rawTitle: String) -> ContentInfo {
        let key = rawTitle as NSString
        if let cached = cache.object(forKey: key) {
            return cached.info
        }
        
        var workingTitle = rawTitle
        var detectedYear: String? = nil
        var s = 0
        var e = 0
        var isSeries = false
        
        // 1. Strip Country Prefixes ("UK | Title")
        if let match = prefixRegex.firstMatch(in: workingTitle, range: NSRange(workingTitle.startIndex..., in: workingTitle)) {
            workingTitle = String(workingTitle[Range(match.range, in: workingTitle)!.upperBound...])
        }
        
        // 2. Detect Series Anchor (S01E01) - Highest Priority
        if let match = seriesAnchorRegex.firstMatch(in: workingTitle, range: NSRange(workingTitle.startIndex..., in: workingTitle)) {
            // Extract S/E
            if let r1 = Range(match.range(at: 1), in: workingTitle),
               let r2 = Range(match.range(at: 2), in: workingTitle) {
                s = Int(workingTitle[r1]) ?? 0
                e = Int(workingTitle[r2]) ?? 0
            }
            
            // Cut title at the anchor. "The.Show.S01E01..." -> "The.Show."
            let cutIndex = Range(match.range, in: workingTitle)!.lowerBound
            workingTitle = String(workingTitle[..<cutIndex])
            isSeries = true
        }
        
        // 3. Detect Year Anchor (2021) - Priority for Movies
        if let match = yearAnchorRegex.firstMatch(in: workingTitle, range: NSRange(workingTitle.startIndex..., in: workingTitle)) {
            if let r = Range(match.range(at: 1), in: workingTitle) {
                detectedYear = String(workingTitle[r])
            }
            
            // Only cut if we haven't already identified it as a series (some series have years in title)
            if !isSeries {
                let cutIndex = Range(match.range, in: workingTitle)!.lowerBound
                workingTitle = String(workingTitle[..<cutIndex])
            }
        }
        
        // 4. Clean The Extracted Title (Basic Chars)
        let separators = CharacterSet(charactersIn: "._-()[]")
        var cleanTitle = workingTitle.components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
        
        // 5. Aggressive Suffix Removal Loop (The "Chillio" Fix)
        var changed = true
        while changed {
            changed = false
            let tokens = cleanTitle.components(separatedBy: " ")
            if let last = tokens.last?.uppercased() {
                if tagsToRemove.contains(last) || (Int(last) != nil && last.count == 4) {
                    cleanTitle = tokens.dropLast().joined(separator: " ")
                    changed = true
                }
            }
        }
        
        // FIX: Better Fallback
        // If normalization stripped everything (or was empty), fallback to the RAW title
        // instead of "Unknown Title" so the user can at least see what it is.
        if cleanTitle.isEmpty || cleanTitle.count < 2 {
            cleanTitle = rawTitle
        }
        
        // 6. Detect Quality & Language from RAW string
        let quality = detectQuality(in: rawTitle)
        let language = detectLanguage(in: rawTitle)
        
        let info = ContentInfo(
            rawTitle: rawTitle,
            normalizedTitle: cleanTitle,
            displayTitle: cleanTitle,
            quality: quality,
            language: language,
            year: detectedYear,
            season: s,
            episode: e,
            isSeries: isSeries || s > 0
        )
        
        cache.setObject(ContentInfoWrapper(info), forKey: key)
        return info
    }
    
    private static func detectQuality(in text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("8k") { return "8K" }
        if lower.contains("2160") || lower.contains("4k") || lower.contains("uhd") { return "4K UHD" }
        if lower.contains("1080") { return "1080p" }
        if lower.contains("720") { return "720p" }
        if lower.contains("480") || lower.contains("sd") { return "SD" }
        return "HD" // Default assumption
    }
    
    private static func detectLanguage(in text: String) -> String? {
        let upper = text.uppercased()
        let tokens = upper.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for token in tokens {
            if let lang = languageMap[token] { return lang }
        }
        return nil
    }
    
    // MARK: - Fuzzy Matching
    
    static func similarity(between s1: String, and s2: String) -> Double {
        let t1 = s1.lowercased().filter { $0.isLetter || $0.isNumber }
        let t2 = s2.lowercased().filter { $0.isLetter || $0.isNumber }
        
        if t1 == t2 { return 1.0 }
        if t1.isEmpty || t2.isEmpty { return 0.0 }
        
        let dist = levenshtein(t1, t2)
        let maxLen = Double(max(t1.count, t2.count))
        return 1.0 - (Double(dist) / maxLen)
    }
    
    private static func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1.utf16)
        let b = Array(s2.utf16)
        
        let m = a.count
        let n = b.count
        var d = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { d[i][0] = i }
        for j in 0...n { d[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = (a[i - 1] == b[j - 1]) ? 0 : 1
                d[i][j] = min(
                    d[i - 1][j] + 1,      // deletion
                    d[i][j - 1] + 1,      // insertion
                    d[i - 1][j - 1] + cost // substitution
                )
            }
        }
        return d[m][n]
    }
}
