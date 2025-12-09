import Foundation
import CoreData

/// Service responsible for "Enriching" content with metadata and artwork from TMDB.
/// Background worker that fixes missing covers and populates Episode Metadata (Titles/Stills).
class EnrichmentService {
    
    private let context: NSManagedObjectContext
    private let tmdbClient: TmdbClient
    
    init(context: NSManagedObjectContext, tmdbClient: TmdbClient) {
        self.context = context
        self.tmdbClient = tmdbClient
    }
    
    // MARK: - Main Enrichment Loop
    
    /// Scans the library for items needing metadata and fetches it efficiently.
    /// - Parameter playlistUrl: The playlist to scan (optional optimization).
    /// - Parameter specificItems: If provided, only these specific items are enriched (High Priority for Search).
    func enrichLibrary(playlistUrl: String? = nil, specificItems: [Channel]? = nil, onStatus: @escaping (String) -> Void) async {
        
        var candidates: [Channel] = []
        
        // 1. Identification Phase
        if let specific = specificItems {
            // High Priority Path (Search Results)
            // Filter only those that actually need enrichment to save API calls
            candidates = specific.filter { needsEnrichment($0) }
        } else {
            // Background Path (Full Library Sync)
            guard let plUrl = playlistUrl else { return }
            await context.perform {
                let req = NSFetchRequest<Channel>(entityName: "Channel")
                req.predicate = NSPredicate(
                    format: "playlistUrl == %@ AND (type == 'movie' OR type == 'series' OR type == 'series_episode')",
                    plUrl
                )
                req.fetchLimit = 5000 // Batch limit
                
                if let results = try? self.context.fetch(req) {
                    candidates = results.filter { self.needsEnrichment($0) }
                }
            }
        }
        
        if candidates.isEmpty { return }
        
        // 2. Grouping (Optimization)
        let groups = Dictionary(grouping: candidates) { ch -> String in
            let info = TitleNormalizer.parse(rawTitle: ch.canonicalTitle ?? ch.title)
            return info.normalizedTitle
        }
        
        let totalGroups = groups.keys.count
        var processed = 0
        
        // 3. Execution Phase
        for (showTitle, items) in groups {
            if Task.isCancelled { break }
            
            processed += 1
            if playlistUrl != nil && processed % 5 == 0 {
                onStatus("Enriching: \(showTitle) (\(processed)/\(totalGroups))")
            }
            
            guard let first = items.first else { continue }
            let type = (first.type == "series" || first.type == "series_episode") ? "series" : "movie"
            
            let year = items.compactMap { TitleNormalizer.parse(rawTitle: $0.canonicalTitle ?? $0.title).year }.first
            
            await processGroup(title: showTitle, year: year, type: type, items: items)
        }
    }
    
    // MARK: - Helper Predicate
    
    private func needsEnrichment(_ ch: Channel) -> Bool {
        // A. Missing Cover?
        if ch.cover == nil || ch.cover?.isEmpty == true { return true }
        
        // B. Episode missing metadata? (Series Only)
        if ch.type == "series_episode" {
            // If title is generic "Episode 1" and we haven't fetched a real name yet
            if (ch.episodeName == nil || ch.episodeName!.isEmpty) { return true }
        }
        
        return false
    }
    
    // MARK: - Group Logic
    
    private func processGroup(title: String, year: String?, type: String, items: [Channel]) async {
        
        // A. Find the Show/Movie ID from TMDB
        guard let match = await tmdbClient.findBestMatch(title: title, year: year, type: type) else { return }
        
        let posterUrl = match.poster.map { "https://image.tmdb.org/t/p/w500\($0)" }
        let backdropUrl = match.backdrop.map { "https://image.tmdb.org/t/p/original\($0)" }
        
        // B. Apply to Series (Deep Fetch)
        if type == "series" {
            // 1. Get Show Details
            guard let showDetails = try? await tmdbClient.getTvDetails(id: match.id) else { return }
            
            // 2. Identify needed seasons
            let neededSeasons = Set(items.map { Int($0.season) }).filter { $0 > 0 }
            
            for seasonNum in neededSeasons {
                // 3. Fetch Season Details
                if let seasonData = try? await tmdbClient.getTvSeason(tvId: match.id, seasonNumber: seasonNum) {
                    
                    // 4. Update Episodes
                    await context.perform { [weak self] in
                        guard let self = self else { return }
                        for ch in items where ch.season == Int16(seasonNum) {
                            if ch.cover == nil { ch.cover = posterUrl }
                            
                            if let epData = seasonData.episodes.first(where: { $0.episodeNumber == Int(ch.episode) }) {
                                ch.episodeName = epData.name
                                ch.overview = epData.overview
                                if let still = epData.stillPath {
                                    ch.backdrop = "https://image.tmdb.org/t/p/w500\(still)"
                                } else {
                                    ch.backdrop = backdropUrl
                                }
                            }
                        }
                    }
                }
            }
            
            // 5. Update Items (Season 0/Specials)
            await context.perform { [weak self] in
                guard let self = self else { return }
                for ch in items where ch.season == 0 {
                    if ch.cover == nil { ch.cover = posterUrl }
                    if ch.backdrop == nil { ch.backdrop = backdropUrl }
                    if ch.overview == nil { ch.overview = showDetails.overview }
                }
                // FIXED: Explicit self capture for method call
                self.saveContext()
            }
            
        } else {
            // C. Apply to Movies
            await context.perform { [weak self] in
                guard let self = self else { return }
                for ch in items {
                    if ch.cover == nil { ch.cover = posterUrl }
                    if ch.backdrop == nil { ch.backdrop = backdropUrl }
                }
                // FIXED: Explicit self capture for method call
                self.saveContext()
            }
        }
    }
    
    private func saveContext() {
        if context.hasChanges {
            try? context.save()
        }
    }
}
