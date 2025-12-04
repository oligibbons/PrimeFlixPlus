import Foundation

// Wrapper to allow NSCache to store Structs (which are value types)
class ContentInfoWrapper: NSObject {
    let info: ContentInfo
    init(_ info: ContentInfo) { self.info = info }
}

struct ContentInfo {
    let rawTitle: String
    let normalizedTitle: String
    let quality: String      // "4K UHD", "1080p", "SD", etc.
    let language: String?    // "English", "French", etc.
    let year: String?
    
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

/// Utility to parse raw IPTV titles into clean metadata.
/// Optimized with static Regex caching for high performance.
enum TitleNormalizer {
    
    // MARK: - Thread-Safe Caching
    // CRITICAL FIX: Caches parsing results to prevent CPU spikes during scrolling.
    private static let cache = NSCache<NSString, ContentInfoWrapper>()
    
    // MARK: - Compiled Regex Patterns
    
    // 1. Year: Matches (1999), [2020], .2021., etc.
    private static let yearRegex = try! NSRegularExpression(
        pattern: "[\\[\\(\\. ](19|20)\\d{2}[\\]\\)\\. ]",
        options: []
    )
    
    // 2. Resolution: Catches 8K, 4K, UHD, 1080p/i, 720p/i, SD, etc.
    private static let resolutionRegex = try! NSRegularExpression(
        pattern: "\\b(8k|4k|uhd|2160p|1440p|1080p|1080i|720p|720i|576p|576i|480p|480i|sd|hd|fhd|qhd|hevc|hq|raw|4k\\+|uhd\\+)\\b",
        options: [.caseInsensitive]
    )
    
    // 3. Video Codecs: Catches h264, h265, av1, 10bit, etc.
    private static let codecRegex = try! NSRegularExpression(
        pattern: "\\b(h\\.?264|h\\.?265|x264|x265|av1|vp9|mpeg-?2|mpeg-?4|avc|hevc|xvid|divx|10bit|12bit)\\b",
        options: [.caseInsensitive]
    )
    
    // 4. Audio: Catches AAC, AC3, Atmos, TrueHD, DTS, 5.1, etc.
    private static let audioRegex = try! NSRegularExpression(
        pattern: "\\b(aac|ac3|eac3|dts|dts-?hd|truehd|atmos|dd5\\.1|dd\\+|5\\.1|7\\.1|mp3|flac|opus|pcm|lpcm|mono|stereo)\\b",
        options: [.caseInsensitive]
    )
    
    // 5. Source & Quality Tags: Catches Bluray, Remux, Web-DL, HDR, etc.
    private static let sourceRegex = try! NSRegularExpression(
        pattern: "\\b(bluray|remux|bdrip|brrip|web-?dl|web-?rip|hdtv|pdtv|dvdrip|cam|ts|tc|scr|screener|r5|dv|hdr|hdr10|hdr10\\+|dolby|vision|imax|upscaled)\\b",
        options: [.caseInsensitive]
    )
    
    // 6. Editions/Junk: Catches "Director's Cut", "Extended", "Unrated"
    private static let junkRegex = try! NSRegularExpression(
        pattern: "\\b(extended|uncut|unrated|remastered|director'?s? ?cut|theatrical|limited|complete|collection|anthology|trilogy|boxset|saga|special ?edition|final ?cut)\\b",
        options: [.caseInsensitive]
    )
    
    // 7. Season/Episode: Catches S01E01, 1x01, Season 1, etc.
    private static let seasonRegex = try! NSRegularExpression(
        pattern: "\\b(s\\d{1,2}e\\d{1,2}|\\d{1,2}x\\d{1,2}|s\\d{1,2}|season ?\\d{1,2}|ep ?\\d{1,2}|episode ?\\d{1,2})\\b",
        options: [.caseInsensitive]
    )
    
    // 8. IPTV Specific Artifacts (The "Dirty" Stuff)
    // Removes: [COLOR red], |UK|, US :, ***, ==>, (1), (2), [Backup]
    private static let iptvArtifactsRegex = try! NSRegularExpression(
        pattern: "(\\[/?(COLOR|B|I)[^\\]]*\\])|(\\|[A-Z]+\\|)|(\\*{2,})|(==>)|(\\(\\d+\\))|(\\[\\d+\\])|(C:\\s*)|(G:\\s*)",
        options: [.caseInsensitive]
    )
    
    // 9. Prefixes: "UK :", "US - ", "001 - ", "VOD |"
    private static let prefixRegex = try! NSRegularExpression(
        pattern: "^(\\d+[\\.\\:\\- ]+)|([A-Z]{2,3}\\s*[\\|\\:\\-]\\s*)",
        options: [.caseInsensitive]
    )
    
    // 10. General Cleanup: Brackets, parentheses, dots, underscores
    private static let cleanupRegex = try! NSRegularExpression(pattern: "[._\\-\\[\\]\\(\\)]", options: [])
    private static let multiSpaceRegex = try! NSRegularExpression(pattern: "\\s+", options: [])
    
    // MARK: - Language Data
    private static let languageMap: [String: String] = [
        "AR": "Arabic", "ARA": "Arabic", "KSA": "Arabic", "EGY": "Arabic",
        "EN": "English", "ENG": "English", "UK": "English", "US": "English", "USA": "English",
        "FR": "French", "FRE": "French", "VF": "French", "VOSTFR": "French", "VOST": "French (Sub)", "QB": "French (Quebec)",
        "ES": "Spanish", "SPA": "Spanish", "ESP": "Spanish", "LATINO": "Spanish", "SP": "Spanish",
        "DE": "German", "GER": "German", "DEU": "German", "AT": "German",
        "IT": "Italian", "ITA": "Italian",
        "RU": "Russian", "RUS": "Russian",
        "TR": "Turkish", "TUR": "Turkish",
        "PT": "Portuguese", "POR": "Portuguese", "BR": "Portuguese", "PT-BR": "Portuguese",
        "NL": "Dutch", "NED": "Dutch",
        "PL": "Polish", "POL": "Polish",
        "HI": "Hindi", "HIN": "Hindi",
        "MULTI": "Multi-Audio", "MULTISUB": "Multi-Audio", "MSUB": "Multi-Audio", "SUB": "Subbed"
    ]
    
    // Compiled regex for languages
    private static let langRegex: NSRegularExpression = {
        let keys = languageMap.keys.joined(separator: "|")
        return try! NSRegularExpression(pattern: "\\b(" + keys + ")\\b", options: [.caseInsensitive])
    }()
    
    // MARK: - Main Parsing
    
    static func parse(rawTitle: String) -> ContentInfo {
        // 1. Check Cache
        let key = rawTitle as NSString
        if let cached = cache.object(forKey: key) {
            return cached.info
        }
        
        // Work with a mutable copy
        var processingTitle = rawTitle.replacingOccurrences(of: "_", with: " ")
                                      .replacingOccurrences(of: ".", with: " ")
        
        // 2. Extract Year (Before cleaning, as brackets might be removed)
        var year: String? = nil
        let range = NSRange(processingTitle.startIndex..<processingTitle.endIndex, in: processingTitle)
        
        if let match = yearRegex.firstMatch(in: processingTitle, options: [], range: range) {
            let yearRange = match.range(at: 1)
            if let r = Range(yearRange, in: processingTitle) {
                let yStr = String(processingTitle[r])
                if let yInt = Int(yStr), yInt >= 1900 && yInt <= 2099 {
                    year = yStr
                    if let fullRange = Range(match.range, in: processingTitle) {
                        processingTitle.replaceSubrange(fullRange, with: " ")
                    }
                }
            }
        }
        
        // 3. Detect Quality (Priority based)
        let lower = processingTitle.lowercased()
        let quality: String
        if lower.contains("8k") { quality = "8K" }
        else if lower.contains("4k") || lower.contains("uhd") || lower.contains("2160") { quality = "4K UHD" }
        else if lower.contains("1080") { quality = "1080p" }
        else if lower.contains("720") { quality = "720p" }
        else if lower.contains("480") || lower.contains("sd") { quality = "SD" }
        else { quality = "SD" }
        
        // 4. Detect Language
        var detectedLang: String? = nil
        let tokens = processingTitle.components(separatedBy: CharacterSet(charactersIn: " -[]()"))
        for token in tokens.reversed() {
            let up = token.uppercased()
            if up.count < 2 { continue }
            if let lang = languageMap[up] {
                detectedLang = lang
                break
            }
        }
        
        // 5. Aggressive Scrubbing
        // Remove IPTV specific artifacts first (Kodi colors, weird pipes)
        processingTitle = strip(processingTitle, regex: iptvArtifactsRegex)
        
        // Remove technical metadata
        processingTitle = strip(processingTitle, regex: resolutionRegex)
        processingTitle = strip(processingTitle, regex: codecRegex)
        processingTitle = strip(processingTitle, regex: audioRegex)
        processingTitle = strip(processingTitle, regex: sourceRegex)
        processingTitle = strip(processingTitle, regex: junkRegex)
        processingTitle = strip(processingTitle, regex: seasonRegex)
        processingTitle = strip(processingTitle, regex: langRegex)
        
        // 6. Remove Prefixes (Country codes, numbers)
        // Repeat twice to catch nested prefixes like "001 | UK | BBC"
        processingTitle = strip(processingTitle, regex: prefixRegex)
        processingTitle = strip(processingTitle, regex: prefixRegex)
        
        // 7. Final Cleanup
        // Remove brackets, dots, leftover symbols
        processingTitle = strip(processingTitle, regex: cleanupRegex, replacement: " ")
        
        // Remove prefixes like "US | Movie Name" if regex missed them
        if processingTitle.contains("|") {
            let parts = processingTitle.split(separator: "|")
            if let last = parts.last { processingTitle = String(last) }
        }
        
        // Collapse multiple spaces
        processingTitle = strip(processingTitle, regex: multiSpaceRegex, replacement: " ")
        
        let finalTitle = processingTitle.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        
        let result = ContentInfo(
            rawTitle: rawTitle,
            normalizedTitle: finalTitle.isEmpty ? rawTitle : finalTitle,
            quality: quality,
            language: detectedLang,
            year: year
        )
        
        // Cache the result
        cache.setObject(ContentInfoWrapper(result), forKey: key)
        
        return result
    }
    
    /// Helper: Replaces regex matches with a replacement string
    private static func strip(_ text: String, regex: NSRegularExpression, replacement: String = " ") -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
    
    /// Generates a strict key for grouping duplicates
    static func generateGroupKey(_ normalizedTitle: String) -> String {
        return normalizedTitle.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
}
