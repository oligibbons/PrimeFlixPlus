import Foundation
import CoreData

/// Service responsible for "Enriching" content with metadata and artwork from TMDB.
/// Background worker that fixes missing covers for Movies AND Series using Smart Fallback logic.
class EnrichmentService {
    
    private let context: NSManagedObjectContext
    private let tmdbClient: TmdbClient
    
    init(context: NSManagedObjectContext, tmdbClient: TmdbClient) {
        self.context = context
        self.tmdbClient = tmdbClient
    }
    
    // MARK: - Main Enrichment Loop
    
    /// Scans a playlist for items without covers and fetches them from TMDB.
    func enrichMovies(playlistUrl: String, onStatus: @escaping (String) -> Void) async {
        
        // 1. Identify candidates (Movies & Series with missing covers)
        var fetchedCandidates: [NSManagedObjectID] = []
        
        await context.perform {
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            // Target items from this playlist that are Movies or Series
            req.predicate = NSPredicate(
                format: "playlistUrl == %@ AND (type == 'movie' OR type == 'series')",
                playlistUrl
            )
            req.fetchLimit = 2000 // Process in chunks
            
            if let results = try? self.context.fetch(req) {
                // Filter: Only process items with no cover, or empty string
                fetchedCandidates = results.filter { ch in
                    guard let c = ch.cover, !c.isEmpty else { return true }
                    // Optional: Add logic to re-check items with generic placeholders if needed
                    return false
                }.map { $0.objectID }
            }
        }
        
        let candidates = fetchedCandidates
        if candidates.isEmpty { return }
        
        // 2. Process in small batches to respect API limits
        let batchSize = 10
        let chunks = stride(from: 0, to: candidates.count, by: batchSize).map {
            Array(candidates[$0..<min($0 + batchSize, candidates.count)])
        }
        
        for (index, chunk) in chunks.enumerated() {
            if index % 5 == 0 {
                let progressMsg = "Enriching Library (\(index * batchSize)/\(candidates.count))..."
                onStatus(progressMsg)
            }
            
            await processBatch(chunk: chunk)
        }
    }
    
    // MARK: - Internal Batch Logic
    
    private func processBatch(chunk: [NSManagedObjectID]) async {
        
        await withTaskGroup(of: (NSManagedObjectID, String?).self) { group in
            for oid in chunk {
                group.addTask {
                    var rawTitle: String = ""
                    var type: String = "movie"
                    
                    // A. Read Data (Thread-safe)
                    await self.context.perform {
                        if let ch = try? self.context.existingObject(with: oid) as? Channel {
                            rawTitle = ch.canonicalTitle ?? ch.title
                            type = ch.type
                        }
                    }
                    
                    if rawTitle.isEmpty { return (oid, nil) }
                    
                    // B. Parse Title (Using the new Anchor-Based Normalizer)
                    let info = TitleNormalizer.parse(rawTitle: rawTitle)
                    
                    // C. Smart Network Call
                    // Uses the new findBestMatch which handles the "Year Mismatch" fallback automatically
                    if let match = await self.tmdbClient.findBestMatch(
                        title: info.normalizedTitle,
                        year: info.year,
                        type: type
                    ) {
                        if let poster = match.poster {
                            return (oid, "https://image.tmdb.org/t/p/w500\(poster)")
                        }
                    }
                    
                    return (oid, nil)
                }
            }
            
            // D. Collect Results
            var updates: [(NSManagedObjectID, String)] = []
            for await (oid, newCover) in group {
                if let cover = newCover {
                    updates.append((oid, cover))
                }
            }
            
            // E. Write Changes (Thread-safe)
            if !updates.isEmpty {
                await self.context.perform {
                    for (oid, cover) in updates {
                        if let ch = try? self.context.existingObject(with: oid) as? Channel {
                            ch.cover = cover
                        }
                    }
                    try? self.context.save()
                }
            }
        }
    }
}
