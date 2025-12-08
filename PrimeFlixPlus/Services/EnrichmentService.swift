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
    func enrichLibrary(playlistUrl: String, onStatus: @escaping (String) -> Void) async {
        
        // 1. Identify candidates (Items missing metadata)
        // We look for items with missing covers OR Series Episodes missing episode names
        var candidates: [Channel] = []
        
        await context.perform {
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            req.predicate = NSPredicate(
                format: "playlistUrl == %@ AND (type == 'movie' OR type == 'series' OR type == 'series_episode')",
                playlistUrl
            )
            // Fetch everything to group them (Memory optimized by only fetching needed properties later if possible,
            // but for grouping we need titles).
            // Limiting to 5000 to prevent OOM on huge playlists.
            req.fetchLimit = 5000
            
            if let results = try? self.context.fetch(req) {
                candidates = results.filter { ch in
                    // Re-process if:
                    // 1. Cover is missing
                    // 2. It's an episode and missing a proper Episode Name
                    if ch.cover == nil || ch.cover?.isEmpty == true { return true }
                    if ch.type == "series_episode" && (ch.episodeName == nil || ch.episodeName!.isEmpty) { return true }
                    return false
                }
            }
        }
        
        if candidates.isEmpty { return }
        
        // 2. Group by Normalized Title (e.g. "Severance") to minimize API calls
        let groups = Dictionary(grouping: candidates) { ch -> String in
            let info = TitleNormalizer.parse(rawTitle: ch.canonicalTitle ?? ch.title)
            return info.normalizedTitle
        }
        
        let totalGroups = groups.keys.count
        var processed = 0
        
        // 3. Process Groups
        for (showTitle, items) in groups {
            processed += 1
            if processed % 5 == 0 {
                onStatus("Enriching: \(showTitle) (\(processed)/\(totalGroups))")
            }
            
            guard let first = items.first else { continue }
            let type = (first.type == "series" || first.type == "series_episode") ? "series" : "movie"
            
            // Extract Year from one of the items if possible
            let year = items.compactMap { TitleNormalizer.parse(rawTitle: $0.canonicalTitle ?? $0.title).year }.first
            
            await processGroup(title: showTitle, year: year, type: type, items: items)
        }
    }
    
    // MARK: - Group Logic
    
    private func processGroup(title: String, year: String?, type: String, items: [Channel]) async {
        
        // A. Find the Show/Movie ID
        guard let match = await tmdbClient.findBestMatch(title: title, year: year, type: type) else { return }
        
        let posterUrl = match.poster.map { "https://image.tmdb.org/t/p/w500\($0)" }
        let backdropUrl = match.backdrop.map { "https://image.tmdb.org/t/p/original\($0)" }
        
        // B. Handle Series Episodes (Deep Fetch)
        if type == "series" {
            // 1. Get Show Details (for generic description/backdrop)
            guard let showDetails = try? await tmdbClient.getTvDetails(id: match.id) else { return }
            
            // 2. Identify needed seasons
            let neededSeasons = Set(items.map { Int($0.season) }).filter { $0 > 0 }
            
            for seasonNum in neededSeasons {
                // 3. Fetch Season Details
                if let seasonData = try? await tmdbClient.getTvSeason(tvId: match.id, seasonNumber: seasonNum) {
                    
                    // 4. Update Episodes in this Season
                    await context.perform {
                        for ch in items where ch.season == Int16(seasonNum) {
                            // Assign Show Poster (so grids look uniform)
                            if ch.cover == nil { ch.cover = posterUrl }
                            
                            // Assign Episode Metadata
                            if let epData = seasonData.episodes.first(where: { $0.episodeNumber == Int(ch.episode) }) {
                                ch.episodeName = epData.name
                                ch.overview = epData.overview
                                if let still = epData.stillPath {
                                    ch.backdrop = "https://image.tmdb.org/t/p/w500\(still)"
                                } else {
                                    ch.backdrop = backdropUrl // Fallback to show backdrop
                                }
                            }
                        }
                    }
                }
            }
            
            // 5. Update Items that didn't match specific episodes (or Season 0)
            await context.perform {
                for ch in items where ch.season == 0 {
                    if ch.cover == nil { ch.cover = posterUrl }
                    if ch.backdrop == nil { ch.backdrop = backdropUrl }
                    if ch.overview == nil { ch.overview = showDetails.overview }
                }
                try? self.context.save()
            }
            
        } else {
            // C. Handle Movies (Simple)
            await context.perform {
                for ch in items {
                    if ch.cover == nil { ch.cover = posterUrl }
                    if ch.backdrop == nil { ch.backdrop = backdropUrl }
                    
                    // Optional: Fetch detailed movie info for overview if needed,
                    // but usually we fetch that on-demand in DetailsView to save bandwidth.
                }
                try? self.context.save()
            }
        }
    }
}
