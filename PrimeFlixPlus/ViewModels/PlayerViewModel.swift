import Foundation
import Combine
import SwiftUI
import TVVLCKit
import CoreData

@MainActor
class PlayerViewModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    
    // MARK: - VLC Engine
    let vlcPlayer = VLCMediaPlayer()
    
    // MARK: - UI State
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = true
    @Published var isError: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showControls: Bool = false
    @Published var showMiniDetails: Bool = false
    
    // MARK: - Auto-Play State
    @Published var showAutoPlay: Bool = false
    @Published var autoPlayCounter: Int = 20
    private var autoPlayTimer: Timer?
    
    // MARK: - Scrubbing State
    @Published var isScrubbing: Bool = false
    private var scrubbingOriginTime: Double?
    
    // MARK: - Seek Stabilization
    // Locks time updates briefly after a seek to prevent "rubber-banding"
    private var targetSeekTime: Double?
    private var seekCommitTime: Date?
    
    // MARK: - Playback Metadata
    @Published var videoTitle: String = ""
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var currentUrl: String = ""
    @Published var channelType: String = "movie"
    @Published var playbackRate: Float = 1.0
    
    // MARK: - Extended Metadata (Overlay)
    @Published var videoOverview: String = ""
    @Published var videoYear: String = ""
    @Published var videoRating: String = ""
    
    // MARK: - Next Episode Logic
    @Published var nextEpisode: Channel? = nil
    @Published var canPlayNext: Bool = false
    
    // MARK: - Favorites
    @Published var isFavorite: Bool = false
    private var currentChannel: Channel?
    
    // MARK: - Dependencies
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
        
        // Reset State
        self.showAutoPlay = false
        self.autoPlayCounter = 20
        self.duration = 0
        self.currentTime = 0
        
        // Load Default Speed from Settings
        let savedSpeed = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
        self.playbackRate = savedSpeed > 0 ? Float(savedSpeed) : 1.0
        
        setupVLC(url: channel.url)
        checkForNextEpisode()
        fetchExtendedMetadata()
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
        vlcPlayer.rate = self.playbackRate // Apply saved speed
        
        vlcPlayer.play()
        self.isPlaying = true
        self.isBuffering = true
        
        startProgressTracking()
        triggerControls()
    }
    
    // MARK: - Metadata Fetching
    
    private func fetchExtendedMetadata() {
        guard let repo = repository, let channel = currentChannel else { return }
        let title = channel.canonicalTitle ?? channel.title
        
        Task.detached {
            let context = repo.container.newBackgroundContext()
            let req = NSFetchRequest<MediaMetadata>(entityName: "MediaMetadata")
            req.predicate = NSPredicate(format: "title == %@", title)
            req.fetchLimit = 1
            
            if let meta = try? context.fetch(req).first {
                let overview = meta.overview ?? ""
                let rating = meta.voteAverage > 0 ? String(format: "%.1f", meta.voteAverage) : ""
                let info = TitleNormalizer.parse(rawTitle: title)
                let year = info.year ?? ""
                
                await MainActor.run {
                    self.videoOverview = overview
                    self.videoRating = rating
                    self.videoYear = year
                }
            } else {
                let info = TitleNormalizer.parse(rawTitle: title)
                await MainActor.run {
                    self.videoYear = info.year ?? ""
                    self.videoOverview = "No details available."
                }
            }
        }
    }
    
    // MARK: - Next Episode Logic
    
    func checkForNextEpisode() {
        // Only valid for series/episodes
        guard let repo = repository,
              let current = currentChannel,
              (current.type == "series" || current.type == "series_episode") else { return }
        
        Task.detached {
            let context = repo.container.newBackgroundContext()
            
            await context.perform {
                if let bgChannel = try? context.existingObject(with: current.objectID) as? Channel {
                    if let next = self.findNextEpisodeInternal(context: context, current: bgChannel) {
                        let nextID = next.objectID
                        Task { @MainActor in
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
    
    private nonisolated func findNextEpisodeInternal(context: NSManagedObjectContext, current: Channel) -> Channel? {
        let title = current.title
        
        // Regex to parse "S01 E01" or "1x01"
        guard let regex = try? NSRegularExpression(pattern: "(?i)(S)(\\d+)\\s*(E)(\\d+)") else { return nil }
        let nsString = title as NSString
        let results = regex.matches(in: title, range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.first, match.numberOfRanges >= 5 else { return nil }
        
        // Extract Season and Episode numbers
        guard let s = Int(nsString.substring(with: match.range(at: 2))),
              let e = Int(nsString.substring(with: match.range(at: 4))) else { return nil }
        
        // 1. Try Next Episode in Same Season
        let nextE = e + 1
        if let next = findSpecificEpisode(context: context, playlistUrl: current.playlistUrl, titlePrefix: String(title.prefix(5)), season: s, episode: nextE) {
            return next
        }
        
        // 2. Try First Episode of Next Season
        let nextS = s + 1
        if let nextSeason = findSpecificEpisode(context: context, playlistUrl: current.playlistUrl, titlePrefix: String(title.prefix(5)), season: nextS, episode: 1) {
            return nextSeason
        }
        
        return nil
    }
    
    private nonisolated func findSpecificEpisode(context: NSManagedObjectContext, playlistUrl: String, titlePrefix: String, season: Int, episode: Int) -> Channel? {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        
        // Loose search first to get candidates
        req.predicate = NSPredicate(
            format: "playlistUrl == %@ AND (type == 'series' OR type == 'series_episode') AND title BEGINSWITH[cd] %@",
            playlistUrl, titlePrefix
        )
        req.fetchLimit = 500
        
        guard let candidates = try? context.fetch(req) else { return nil }
        
        let targetS = String(format: "S%02d", season)
        let targetE = String(format: "E%02d", episode)
        
        // Strict in-memory check
        return candidates.first { ch in
            let t = ch.title.uppercased()
            return t.contains(targetS) && t.contains(targetE)
        }
    }
    
    // MARK: - Auto Play Logic
    
    func triggerAutoPlay() {
        guard canPlayNext else {
            // No next episode? Just exit controls.
            triggerControls(forceShow: true)
            return
        }
        
        // Start countdown
        self.showAutoPlay = true
        self.autoPlayCounter = 20
        self.showControls = false // Hide standard controls
        
        autoPlayTimer?.invalidate()
        autoPlayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.autoPlayCounter > 0 {
                self.autoPlayCounter -= 1
            } else {
                self.confirmAutoPlay()
            }
        }
    }
    
    func cancelAutoPlay() {
        autoPlayTimer?.invalidate()
        showAutoPlay = false
        triggerControls(forceShow: true)
    }
    
    func confirmAutoPlay() {
        autoPlayTimer?.invalidate()
        showAutoPlay = false
        if let next = nextEpisode {
            // Signal view to switch
            // We use a closure in View to handle the switch
            NotificationCenter.default.post(name: NSNotification.Name("PlayNextEpisode"), object: next)
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
                
                // Get Duration
                if let len = player.media?.length, len.intValue > 0 {
                    self.duration = Double(len.intValue) / 1000.0
                }
                
                // Ensure Rate is applied
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
                
            case .ended:
                self.isPlaying = false
                self.isBuffering = false
                // Check for auto-play instead of just showing controls
                if self.canPlayNext {
                    self.triggerAutoPlay()
                } else {
                    self.triggerControls(forceShow: true)
                }
                
            case .stopped:
                self.isPlaying = false
                self.isBuffering = false
                self.triggerControls(forceShow: true)
                
            default:
                break
            }
        }
    }
    
    @objc nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            self.updateTimeFromPlayer()
        }
    }
    
    private func updateTimeFromPlayer() {
        // 1. Don't update if scrubbing
        if isScrubbing { return }
        
        let playerTime = Double(vlcPlayer.time.intValue) / 1000.0
        
        // 2. SEEK STABILIZATION LOCK
        if let commit = seekCommitTime {
            if Date().timeIntervalSince(commit) < 2.0 {
                // We are locked. Keep displaying the target seek time.
                return
            } else {
                // Lock expired. Player should be stable now.
                self.seekCommitTime = nil
                self.targetSeekTime = nil
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
            // FIX: Do NOT auto-open mini details on pause.
            // User requested explicit swipe only.
        } else {
            vlcPlayer.play()
            self.isPlaying = true
            withAnimation { self.showMiniDetails = false }
        }
        triggerControls(forceShow: true)
    }
    
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
    
    func seekForward(seconds: Int = 10) { seek(by: seconds) }
    func seekBackward(seconds: Int = 10) { seek(by: -seconds) }
    
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
    
    func startScrubbing(translation: CGFloat, screenWidth: CGFloat) {
        // FIX: If duration is unknown (0), scrubbing will calculate 0 and reset the video.
        guard duration > 0 else { return }
        
        isScrubbing = true
        triggerControls(forceShow: true)
        
        if scrubbingOriginTime == nil {
            scrubbingOriginTime = currentTime
        }
        
        guard let origin = scrubbingOriginTime else { return }
        
        let baseSeekWindow = max(120.0, duration * 0.10)
        let percentage = Double(translation / screenWidth)
        let timeDelta = baseSeekWindow * percentage
        
        var newTime = origin + timeDelta
        newTime = max(0, min(newTime, duration))
        
        self.currentTime = newTime
    }
    
    func endScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        scrubbingOriginTime = nil
        
        // Only commit if we have a valid time (and scrubbing didn't abort)
        if currentTime > 0 {
            let ms = Int32(currentTime * 1000)
            commitSeek(to: ms)
        }
    }
    
    private func commitSeek(to ms: Int32) {
        vlcPlayer.time = VLCTime(int: ms)
        targetSeekTime = Double(ms) / 1000.0
        seekCommitTime = Date()
    }
    
    func triggerControls(forceShow: Bool = false) {
        controlHideTimer?.invalidate()
        withAnimation { showControls = true }
        
        // Hide only if playing and not in a special state
        // Added check for showAutoPlay to prevent controls from hiding while auto-play is counting down
        if (vlcPlayer.isPlaying || forceShow == false) && !isError && !showAutoPlay {
            controlHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.vlcPlayer.isPlaying && !self.isScrubbing && !self.showMiniDetails && !self.showAutoPlay {
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
    
    func cleanup() {
        print("🛑 Cleaning up VLC")
        progressTimer?.invalidate()
        controlHideTimer?.invalidate()
        autoPlayTimer?.invalidate()
        if vlcPlayer.isPlaying { vlcPlayer.stop() }
        vlcPlayer.delegate = nil
        vlcPlayer.drawable = nil
    }
    
    // MARK: - Helpers
    
    private func startProgressTracking() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateTimeFromPlayer()
            
            // Robust check: If VLC says it's playing, dismiss buffering immediately
            if self.vlcPlayer.isPlaying {
                if self.isBuffering { self.isBuffering = false }
                if !self.isPlaying { self.isPlaying = true }
            }
            
            // Duration Check (Retrying if 0)
            if self.duration == 0, let len = self.vlcPlayer.media?.length, len.intValue > 0 {
                self.duration = Double(len.intValue) / 1000.0
            }
            
            // Save Progress
            if Int(self.currentTime) % 5 == 0 {
                guard let repo = self.repository, let channel = self.currentChannel else { return }
                let pos = Int64(self.currentTime * 1000)
                let dur = Int64(self.duration * 1000)
                
                if (pos > 10000 && dur > 0) || channel.type == "live" {
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
