import Foundation
import Combine
import SwiftUI
import TVVLCKit
import CoreData

@MainActor
class PlayerViewModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    
    // VLC Engine
    let vlcPlayer = VLCMediaPlayer()
    
    // UI State
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = true
    @Published var isError: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showControls: Bool = false
    @Published var showMiniDetails: Bool = false // NEW: Mini Details Overlay
    
    // Scrubbing State
    @Published var isScrubbing: Bool = false
    private var scrubbingOriginTime: Double?
    
    // Seek Stabilization
    // We ignore player updates until the player "catches up" to this time.
    private var targetSeekTime: Double?
    private var seekCommitTime: Date?
    
    // Metadata
    @Published var videoTitle: String = ""
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var currentUrl: String = ""
    @Published var channelType: String = "movie" // To determine if we show "Next Episode"
    
    // NEW: Extended Metadata for Mini-Details Overlay
    @Published var videoOverview: String = ""
    @Published var videoYear: String = ""
    @Published var videoRating: String = ""
    
    // Playback Speed
    @Published var playbackRate: Float = 1.0
    
    // Next Episode Logic
    @Published var nextEpisode: Channel? = nil
    @Published var canPlayNext: Bool = false
    
    // Favorites
    @Published var isFavorite: Bool = false
    private var currentChannel: Channel?
    
    // Dependencies
    private var repository: PrimeFlixRepository?
    private var progressTimer: Timer?
    private var controlHideTimer: Timer?
    
    // MARK: - Configuration
    
    func configure(repository: PrimeFlixRepository, channel: Channel) {
        self.repository = repository
        self.currentChannel = channel
        self.videoTitle = channel.title
        self.isFavorite = channel.isFavorite
        self.currentUrl = channel.url
        self.channelType = channel.type
        
        // Load Default Speed from Settings
        let savedSpeed = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
        self.playbackRate = savedSpeed > 0 ? Float(savedSpeed) : 1.0
        
        setupVLC(url: channel.url)
        checkForNextEpisode()
        fetchExtendedMetadata() // Trigger metadata fetch
    }
    
    // MARK: - VLC Setup
    
    private func setupVLC(url: String) {
        guard let mediaUrl = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url) else {
            reportError("Invalid URL", reason: url)
            return
        }
        
        let media = VLCMedia(url: mediaUrl)
        media.addOptions([
            "network-caching": 3000,
            "clock-jitter": 0,
            "clock-synchro": 0
        ])
        
        vlcPlayer.media = media
        vlcPlayer.delegate = self
        
        // Apply Playback Rate
        vlcPlayer.rate = self.playbackRate
        
        vlcPlayer.play()
        self.isPlaying = true
        self.isBuffering = true
        
        startProgressTracking()
        triggerControls()
    }
    
    // MARK: - Metadata Fetching
    
    /// Fetches Synopsis, Year, and Rating from Core Data (MediaMetadata) or parses title
    private func fetchExtendedMetadata() {
        guard let repo = repository, let channel = currentChannel else { return }
        let title = channel.canonicalTitle ?? channel.title
        
        Task.detached {
            let context = repo.container.newBackgroundContext()
            // 1. Try to find cached metadata (populated by DetailsView)
            let req = NSFetchRequest<MediaMetadata>(entityName: "MediaMetadata")
            req.predicate = NSPredicate(format: "title == %@", title)
            req.fetchLimit = 1
            
            if let meta = try? context.fetch(req).first {
                let overview = meta.overview ?? ""
                let rating = meta.voteAverage > 0 ? String(format: "%.1f", meta.voteAverage) : ""
                
                // If metadata lacks year, parse it from the title
                let info = TitleNormalizer.parse(rawTitle: title)
                let year = info.year ?? ""
                
                await MainActor.run {
                    self.videoOverview = overview
                    self.videoRating = rating
                    self.videoYear = year
                }
            } else {
                // 2. Fallback: Parse basic info from the filename/title
                let info = TitleNormalizer.parse(rawTitle: title)
                await MainActor.run {
                    self.videoYear = info.year ?? ""
                    self.videoOverview = "No details available."
                }
            }
        }
    }
    
    // MARK: - VLC Delegate Methods
    
    @objc nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            
            switch player.state {
            case .buffering:
                self.isBuffering = true
                self.triggerControls()
            case .playing:
                self.isBuffering = false
                self.isPlaying = true
                self.isError = false
                if let len = player.media?.length, len.intValue > 0 {
                    self.duration = Double(len.intValue) / 1000.0
                }
                // Enforce rate on successful start
                if player.rate != self.playbackRate {
                    player.rate = self.playbackRate
                }
                self.triggerControls()
            case .paused:
                self.isPlaying = false
                self.isBuffering = false
                self.triggerControls(forceShow: true)
            case .error:
                self.reportError("Playback Error", reason: "Stream failed to load.")
            case .ended, .stopped:
                self.isPlaying = false
                self.isBuffering = false
                self.triggerControls(forceShow: true)
                // Auto-Play next logic could go here in v2
            default:
                break
            }
        }
    }
    
    @objc nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            // Use common logic for time updates
            self.updateTimeFromPlayer()
        }
    }
    
    private func updateTimeFromPlayer() {
        // 1. Don't update if scrubbing
        if isScrubbing { return }
        
        let playerTime = Double(vlcPlayer.time.intValue) / 1000.0
        
        // 2. Seek Stabilization Logic
        // If we recently sought to a time, ignore "old" time reports from the player
        // until it reports a time close to (or after) our target.
        if let target = targetSeekTime, let commit = seekCommitTime {
            // Safety timeout: After 3 seconds, accept whatever the player says to prevent getting stuck
            if Date().timeIntervalSince(commit) > 3.0 {
                self.targetSeekTime = nil
                self.seekCommitTime = nil
            } else {
                // If player is still behind the target (by > 2 seconds), ignore it
                if playerTime < (target - 2.0) {
                    return
                }
                // Player has caught up
                self.targetSeekTime = nil
                self.seekCommitTime = nil
            }
        }
        
        self.currentTime = playerTime
    }
    
    // MARK: - Controls
    
    func assignView(_ view: UIView) {
        vlcPlayer.drawable = view
    }
    
    func togglePlayPause() {
        if vlcPlayer.isPlaying {
            vlcPlayer.pause()
            self.isPlaying = false
            // Show Mini Details on Pause
            withAnimation { self.showMiniDetails = true }
        } else {
            vlcPlayer.play()
            self.isPlaying = true
            withAnimation { self.showMiniDetails = false }
        }
        triggerControls(forceShow: true)
    }
    
    // MARK: - Playback Logic Features (New)
    
    func setPlaybackSpeed(_ speed: Float) {
        self.playbackRate = speed
        vlcPlayer.rate = speed
        triggerControls(forceShow: true)
    }
    
    func restartPlayback() {
        vlcPlayer.time = VLCTime(int: 0)
        self.currentTime = 0
        vlcPlayer.play()
        self.isPlaying = true
        withAnimation { self.showMiniDetails = false }
        triggerControls(forceShow: true)
    }
    
    func checkForNextEpisode() {
        guard let repo = repository, let current = currentChannel, current.type == "series" else { return }
        
        Task.detached {
            let context = repo.container.newBackgroundContext()
            // Using a detached task to perform background fetch
            
            await context.perform {
                // Fetch the background context version of current channel
                if let bgChannel = try? context.existingObject(with: current.objectID) as? Channel {
                    if let next = self.findNextEpisodeInternal(context: context, current: bgChannel) {
                        let nextID = next.objectID
                        Task { @MainActor in
                            // Re-fetch on main context to update UI safely
                            if let mainNext = try? repo.container.viewContext.existingObject(with: nextID) as? Channel {
                                self.nextEpisode = mainNext
                                self.canPlayNext = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Helper to find next episode
    // MARK: - Concurrency Fix: nonisolated to run safely on background thread
    private nonisolated func findNextEpisodeInternal(context: NSManagedObjectContext, current: Channel) -> Channel? {
        let title = current.title
        // Simple S01E01 parser
        guard let regex = try? NSRegularExpression(pattern: "(?i)(S)(\\d+)\\s*(E)(\\d+)") else { return nil }
        let nsString = title as NSString
        let results = regex.matches(in: title, range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.first, match.numberOfRanges >= 5 else { return nil }
        guard let s = Int(nsString.substring(with: match.range(at: 2))),
              let e = Int(nsString.substring(with: match.range(at: 4))) else { return nil }
        
        // Try Next Episode
        let nextE = e + 1
        let prefix = String(title.prefix(5)) // Optimization
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.predicate = NSPredicate(
            format: "playlistUrl == %@ AND type == 'series' AND title BEGINSWITH[cd] %@",
            current.playlistUrl, prefix
        )
        req.fetchLimit = 500
        
        if let candidates = try? context.fetch(req) {
             return candidates.first { ch in
                 let t = ch.title.uppercased()
                 return t.contains(String(format: "S%02dE%02d", s, nextE))
             }
        }
        return nil
    }
    
    // MARK: - Discrete Seeking (Click)
    
    func seekForward(seconds: Int = 10) {
        seek(by: seconds)
    }
    
    func seekBackward(seconds: Int = 10) {
        seek(by: -seconds)
    }
    
    private func seek(by seconds: Int) {
        guard vlcPlayer.isSeekable else { return }
        
        let currentMs = Int32(self.currentTime * 1000)
        let deltaMs = Int32(seconds * 1000)
        let newTimeMs = currentMs + deltaMs
        let maxTimeMs = Int32(duration * 1000)
        let safeTimeMs = max(0, min(newTimeMs, maxTimeMs))
        
        self.currentTime = Double(safeTimeMs) / 1000.0
        
        commitSeek(to: safeTimeMs)
        triggerControls(forceShow: true)
    }
    
    // MARK: - Continuous Scrubbing (Drag)
    
    func startScrubbing(translation: CGFloat, screenWidth: CGFloat) {
        isScrubbing = true
        triggerControls(forceShow: true)
        
        if scrubbingOriginTime == nil {
            scrubbingOriginTime = currentTime
        }
        
        guard let origin = scrubbingOriginTime else { return }
        
        // Tuning: Full swipe width = 90 seconds (Fine scrubbing)
        // or dynamic based on content length? Let's use a dynamic window.
        // For a 2 hour movie, we want a swipe to move maybe 10 minutes.
        let baseSeekWindow = max(120.0, duration * 0.10)
        let percentage = Double(translation / screenWidth)
        let timeDelta = baseSeekWindow * percentage
        
        var newTime = origin + timeDelta
        newTime = max(0, min(newTime, duration))
        
        self.currentTime = newTime
    }
    
    func endScrubbing() {
        isScrubbing = false
        scrubbingOriginTime = nil
        
        let ms = Int32(currentTime * 1000)
        commitSeek(to: ms)
    }
    
    private func commitSeek(to ms: Int32) {
        vlcPlayer.time = VLCTime(int: ms)
        
        // Set lock
        targetSeekTime = Double(ms) / 1000.0
        seekCommitTime = Date()
    }
    
    // MARK: - UI Management
    
    func triggerControls(forceShow: Bool = false) {
        controlHideTimer?.invalidate()
        withAnimation { showControls = true }
        
        if (vlcPlayer.isPlaying || forceShow == false) && !isError {
            controlHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.vlcPlayer.isPlaying && !self.isScrubbing && !self.showMiniDetails {
                    withAnimation { self.showControls = false }
                }
            }
        }
    }
    
    func toggleFavorite() {
        guard let channel = currentChannel, let repo = repository else { return }
        repo.toggleFavorite(channel)
        self.isFavorite.toggle()
        triggerControls(forceShow: true)
    }
    
    func toggleMiniDetails() {
        withAnimation {
            showMiniDetails.toggle()
        }
    }
    
    func cleanup() {
        print("🛑 Cleaning up VLC")
        progressTimer?.invalidate()
        controlHideTimer?.invalidate()
        if vlcPlayer.isPlaying { vlcPlayer.stop() }
        vlcPlayer.delegate = nil
        vlcPlayer.drawable = nil
    }
    
    // MARK: - Helpers
    
    private func startProgressTracking() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Poll for time (Backup for delegate)
            self.updateTimeFromPlayer()
            
            // Update Duration if needed
            if self.duration == 0, let len = self.vlcPlayer.media?.length, len.intValue > 0 {
                self.duration = Double(len.intValue) / 1000.0
            }
            
            // Sync Play/Pause state
            if self.vlcPlayer.isPlaying && !self.isPlaying {
                self.isPlaying = true
                self.isBuffering = false
            }
            
            if self.currentTime > 0 && self.isBuffering {
                Task { @MainActor in self.isBuffering = false }
            }
            
            // Save Progress
            if Int(self.currentTime) % 5 == 0 {
                guard let repo = self.repository, let channel = self.currentChannel else { return }
                let pos = Int64(self.currentTime * 1000)
                let dur = Int64(self.duration * 1000)
                
                let isVLCPlaying = self.vlcPlayer.isPlaying || self.vlcPlayer.state == .playing
                
                if (pos > 10000 && dur > 0 && isVLCPlaying) || channel.type == "live" {
                    Task { @MainActor in
                        repo.saveProgress(url: self.currentUrl, pos: pos, dur: dur)
                    }
                }
            }
        }
    }
    
    private func reportError(_ title: String, reason: String) {
        self.isError = true
        self.errorMessage = "\(title): \(reason)"
        self.isBuffering = false
        triggerControls(forceShow: true)
    }
}
