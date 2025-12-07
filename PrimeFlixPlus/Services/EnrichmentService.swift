import Foundation
import CoreData

/// Service responsible for "Enriching" content with metadata and artwork from TMDB.
/// It runs in the background to fix missing covers for Movies/Series.
class EnrichmentService {
    
    private let context: NSManagedObjectContext
    private let tmdbClient: TmdbClient
    
    init(context: NSManagedObjectContext, tmdbClient: TmdbClient) {
        self.context = context
        self.tmdbClient = tmdbClient
    }
    
    // MARK: - Main Enrichment Loop
    
    /// Scans a playlist for items without covers and fetches them from TMDB.
    /// - Parameters:
    ///   - playlistUrl: The playlist to scan.
    ///   - onStatus: Callback for UI updates (e.g. "Enriching 10/500...").
    func enrichMovies(playlistUrl: String, onStatus: @escaping (String) -> Void) async {
        
        // 1. Identify candidates (Movies with missing/generic covers)
        var fetchedCandidates: [NSManagedObjectID] = []
        
        await context.perform {
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            // Target movies from this playlist
            // Check for nil cover OR empty string
            req.predicate = NSPredicate(format: "playlistUrl == %@ AND type == 'movie'", playlistUrl)
            req.fetchLimit = 2000 // Batch limit
            
            if let results = try? self.context.fetch(req) {
                // Heuristic: If cover is nil, empty, or likely a generic Xtream icon
                fetchedCandidates = results.filter { ch in
                    guard let c = ch.cover, !c.isEmpty else { return true }
                    // Add logic here if you want to replace specific "default" icons
                    return false
                }.map { $0.objectID }
            }
        }
        
        let candidates = fetchedCandidates // Freeze for concurrency
        if candidates.isEmpty { return }
        
        // 2. Process in batches to respect API limits
        let batchSize = 10
        let chunks = stride(from: 0, to: candidates.count, by: batchSize).map {
            Array(candidates[$0..<min($0 + batchSize, candidates.count)])
        }
        
        for (index, chunk) in chunks.enumerated() {
            // Update UI occasionally (every 5 batches)
            if index % 5 == 0 {
                let progressMsg = "Enriching Movies (\(index * batchSize)/\(candidates.count))..."
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
                    
                    // A. Read Title (Context Block)
                    await self.context.perform {
                        if let ch = try? self.context.existingObject(with: oid) as? Channel {
                            rawTitle = ch.canonicalTitle ?? ch.title
                        }
                    }
                    
                    if rawTitle.isEmpty { return (oid, nil) }
                    
                    // B. Network Call (No Context Lock)
                    // Parse & Search
                    let info = TitleNormalizer.parse(rawTitle: rawTitle)
                    if let results = try? await self.tmdbClient.searchMovie(query: info.normalizedTitle, year: info.year) {
                        if let best = results.first, let path = best.posterPath {
                            return (oid, "https://image.tmdb.org/t/p/w500\(path)")
                        }
                    }
                    return (oid, nil)
                }
            }
            
            // C. Collect Results
            var updates: [(NSManagedObjectID, String)] = []
            for await (oid, newCover) in group {
                if let cover = newCover {
                    updates.append((oid, cover))
                }
            }
            
            // D. Write Changes (Context Block)
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
