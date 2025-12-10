import Foundation
import CoreData

/// Service responsible for fetching, persisting, and querying Electronic Program Guide (EPG) data.
/// Optimized to handle "Short EPG" (next 12 hours) efficiently without blocking the UI.
class EpgService {
    
    private let context: NSManagedObjectContext
    private let xtreamClient: XtreamClient
    
    // In-Memory cache to prevent redundant API hits within short windows (e.g. scrolling)
    private var lastFetchTime: [String: Date] = [:]
    
    init(context: NSManagedObjectContext, xtreamClient: XtreamClient = XtreamClient()) {
        self.context = context
        self.xtreamClient = xtreamClient
    }
    
    // MARK: - Public API
    
    /// Fetches EPG for a specific list of channels (e.g. Favorites lane).
    /// Safe to call repeatedly; checks cache timestamps before hitting network.
    func refreshEpg(for channels: [Channel]) async {
        let now = Date()
        var targets: [Channel] = []
        
        // 1. Filter candidates (Don't refetch if fetched < 30 mins ago)
        for ch in channels {
            if let last = lastFetchTime[ch.url], now.timeIntervalSince(last) < 1800 {
                continue
            }
            targets.append(ch)
        }
        
        if targets.isEmpty { return }
        
        // 2. Process in Batches
        // We do this serially or in small groups to avoid 429 Too Many Requests
        for channel in targets {
            if Task.isCancelled { break }
            await fetchAndSave(channel: channel)
        }
    }
    
    /// Returns currently active programs for a list of channels.
    /// Used for "Now Playing" metadata on cards.
    func getCurrentPrograms(for channels: [Channel]) -> [String: Programme] {
        let ids = channels.map { $0.url } // Using URL as ID in our schema
        if ids.isEmpty { return [:] }
        
        let now = Date()
        let req = NSFetchRequest<Programme>(entityName: "Programme")
        req.predicate = NSPredicate(
            format: "channelId IN %@ AND start <= %@ AND end >= %@",
            ids, now as NSDate, now as NSDate
        )
        
        var map: [String: Programme] = [:]
        context.performAndWait {
            if let results = try? context.fetch(req) {
                for prog in results {
                    map[prog.channelId] = prog
                }
            }
        }
        return map
    }
    
    /// Returns the full schedule for a specific channel (sorted by time).
    func getSchedule(for channel: Channel) -> [Programme] {
        let req = NSFetchRequest<Programme>(entityName: "Programme")
        req.predicate = NSPredicate(format: "channelId == %@", channel.url)
        req.sortDescriptors = [NSSortDescriptor(key: "start", ascending: true)]
        
        var results: [Programme] = []
        context.performAndWait {
            results = (try? context.fetch(req)) ?? []
        }
        return results
    }
    
    /// Search within the EPG (e.g. "Football", "News").
    func searchPrograms(query: String) -> [Programme] {
        let req = NSFetchRequest<Programme>(entityName: "Programme")
        req.predicate = NSPredicate(format: "title CONTAINS[cd] %@ OR desc CONTAINS[cd] %@", query, query)
        req.sortDescriptors = [NSSortDescriptor(key: "start", ascending: true)]
        req.fetchLimit = 50
        
        var results: [Programme] = []
        context.performAndWait {
            results = (try? context.fetch(req)) ?? []
        }
        return results
    }
    
    // MARK: - Internal Logic
    
    private func fetchAndSave(channel: Channel) async {
        // Extract Stream ID from URL
        // URL format: .../live/user/pass/STREAM_ID.m3u8
        guard let streamId = extractStreamId(from: channel.url) else { return }
        let input = XtreamInput.decodeFromPlaylistUrl(channel.playlistUrl)
        
        do {
            let listings = try await xtreamClient.getShortEPG(input: input, streamId: streamId)
            
            await context.perform {
                // 1. Clear old future data for this channel to prevent overlaps/stale data
                // We only delete future stuff to allow overwrite. Past stuff is cleaned up separately.
                let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Programme")
                fetch.predicate = NSPredicate(format: "channelId == %@ AND start > %@", channel.url, Date() as NSDate)
                let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
                _ = try? self.context.execute(deleteReq)
                
                // 2. Insert new data
                for item in listings {
                    guard let start = item.startTime, let end = item.endTime else { continue }
                    
                    // Deduplication check: Ensure we don't insert exact duplicate ID if API returns overlapping history
                    // (Though batch delete above handles most cases, sometimes "current" program overlaps)
                    
                    let prog = Programme(
                        context: self.context,
                        channelId: channel.url,
                        title: item.title?.base64DecodedIfPossible ?? "Unknown Program",
                        desc: item.desc?.base64DecodedIfPossible,
                        icon: nil, // Xtream Short EPG rarely sends program icons, usually channel icon suffices
                        start: start,
                        end: end,
                        playlistUrl: channel.playlistUrl
                    )
                    // Custom ID generation to ensure uniqueness
                    prog.id = "\(channel.url)_\(Int(start.timeIntervalSince1970))"
                }
                
                try? self.context.save()
            }
            
            // Update cache timestamp
            lastFetchTime[channel.url] = Date()
            
        } catch {
            print("EPG Fetch failed for \(channel.title): \(error.localizedDescription)")
        }
    }
    
    /// Runs a cleanup job to remove programs that ended more than 4 hours ago.
    /// Keeps the database size small (constraint: "only need next 6-12 hours").
    func pruneExpiredPrograms() {
        context.perform {
            let cutoff = Date().addingTimeInterval(-4 * 3600) // 4 hours ago
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Programme")
            fetch.predicate = NSPredicate(format: "end < %@", cutoff as NSDate)
            let deleteReq = NSBatchDeleteRequest(fetchRequest: fetch)
            
            do {
                _ = try self.context.execute(deleteReq)
                try self.context.save()
            } catch {
                print("EPG Prune failed: \(error)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func extractStreamId(from url: String) -> Int? {
        // .../12345.m3u8 -> 12345
        let lastPart = url.components(separatedBy: "/").last ?? ""
        let idPart = lastPart.replacingOccurrences(of: ".m3u8", with: "")
                             .replacingOccurrences(of: ".ts", with: "")
        return Int(idPart)
    }
}

// Helper for potentially Base64 strings (common in IPTV)
private extension String {
    var base64DecodedIfPossible: String {
        // Simple heuristic: If it looks like base64 and decodes to valid UTF8, use it.
        // Otherwise return self.
        if self.count > 20, let data = Data(base64Encoded: self), let text = String(data: data, encoding: .utf8) {
            return text
        }
        return self
    }
}
