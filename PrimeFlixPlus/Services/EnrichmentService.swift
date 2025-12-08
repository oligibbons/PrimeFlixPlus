import Foundation
import CoreData

/// Service responsible for "Enriching" content with metadata and artwork from TMDB.
/// Background worker that fixes missing covers for Movies AND Series.
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
            // FIX: Now checking both 'movie' and 'series' types
            req.predicate = NSPredicate(
                format: "playlistUrl == %@ AND (type == 'movie' OR type == 'series')",
                playlistUrl
            )
            req.fetchLimit = 2000
            
            if let results = try? self.context.fetch(req) {
                // Filter for missing or empty covers
                fetchedCandidates = results.filter { ch in
                    guard let c = ch.cover, !c.isEmpty else { return true }
                    return false
                }.map { $0.objectID }
            }
        }
        
        let candidates = fetchedCandidates
        if candidates.isEmpty { return }
        
        // 2. Process in batches
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
                    
                    // A. Read Data
                    await self.context.perform {
                        if let ch = try? self.context.existingObject(with: oid) as? Channel {
                            rawTitle = ch.canonicalTitle ?? ch.title
                            type = ch.type
                        }
                    }
                    
                    if rawTitle.isEmpty { return (oid, nil) }
                    
                    // B. Parse & Network Call
                    let info = TitleNormalizer.parse(rawTitle: rawTitle)
                    
                    // FIX: Branch logic based on type
                    if type == "series" {
                        if let results = try? await self.tmdbClient.searchTv(query: info.normalizedTitle, year: info.year) {
                            if let best = results.first, let path = best.posterPath {
                                return (oid, "https://image.tmdb.org/t/p/w500\(path)")
                            }
                        }
                    } else {
                        if let results = try? await self.tmdbClient.searchMovie(query: info.normalizedTitle, year: info.year) {
                            if let best = results.first, let path = best.posterPath {
                                return (oid, "https://image.tmdb.org/t/p/w500\(path)")
                            }
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
            
            // D. Write Changes
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
