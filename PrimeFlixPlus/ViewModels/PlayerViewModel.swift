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
    @Published var showTrackSelection: Bool = false
    
    // MARK: - Track Management
    @Published var audioTracks: [String] = []
    @Published var currentAudioIndex: Int = 0
    @Published var subtitleTracks: [String] = []
    @Published var currentSubtitleIndex: Int = 0
    
    // MARK: - Auto-Play State
    @Published var showAutoPlay: Bool = false
    @Published var autoPlayCounter: Int = 20
    private var autoPlayTimer: Timer?
    
    // MARK: - Scrubbing State
    @Published var isScrubbing: Bool = false
    private var scrubbingOriginTime: Double?
    
    // MARK: - Seek Stabilization
    private var targetSeekTime: Double?
    private var seekCommitTime: Date?
    
    // MARK: - Playback Metadata
    @Published var videoTitle: String = ""
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var currentUrl: String = ""
    @Published var channelType: String = "movie"
    @Published var playbackRate: Float = 1.0
    
    // MARK: - Extended Metadata
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
    private var timeoutTimer: Timer?
    private var lastSavedTime: Double = 0
    
    // MARK: - Configuration
    
    func configure(repository: PrimeFlixRepository, channel: Channel) {
        self.repository = repository
        self.currentChannel = channel
        self.videoTitle = channel.title
        self.isFavorite = channel.isFavorite
        self.currentUrl = channel.url
        self.channelType = channel.type
        
        self.showAutoPlay = false
        self.autoPlayCounter = 20
        self.duration = 0
        self.currentTime = 0
        self.audioTracks = []
        self.subtitleTracks = []
        self.isError = false
        self.errorMessage = nil
        
        let savedSpeed = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
        self.playbackRate = savedSpeed > 0 ? Float(savedSpeed) : 1.0
        
        setupVLC(url: channel.url, type: channel.type)
        checkForNextEpisode()
        fetchExtendedMetadata()
    }
    
    // MARK: - VLC Setup
    
    private func setupVLC(url: String, type: String) {
        // Safe URL Creation: Prevents double-encoding if the URL is already valid
        // but handles spaces/special chars if they are raw.
        var urlObj = URL(string: url)
        if urlObj == nil {
            if let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlObj = URL(string: encoded)
            }
        }
        
        guard let mediaUrl = urlObj else {
            reportError("Invalid URL", reason: "Could not parse stream link.")
            return
        }
        
        let media = VLCMedia(url: mediaUrl)
        
        // Smart Buffering Logic
        let cacheSize: Int
        if type == "live" {
            cacheSize = 2000 // Increased slightly for stability
        } else if let q = currentChannel?.quality, q.contains("4K") {
            cacheSize = 10000 // 10s buffer for 4K
        } else {
            cacheSize = 5000 // 5s buffer standard
        }
        
        // NUCLEAR OPTION: Robust Network Settings
        // We use 'okhttp' user-agent as it's the standard for Android networking
        // and often bypasses "Browser" or "Player" specific blocks.
        let options: [String: Any] = [
            "network-caching": cacheSize,
            "clock-jitter": 0,
            "clock-synchro": 0,
            "http-continuous": true,      // Ignore stream discontinuities (Essential for throttling)
            "http-reconnect": true,       // Aggressively reconnect on drop
            ":http-continuous": true,     // Force apply to media
            ":http-reconnect": true,      // Force apply to media
            "http-user-agent": "okhttp/3.12.1",
            ":http-user-agent": "okhttp/3.12.1"
        ]
        
        media.addOptions(options)
        
        vlcPlayer.media = media
        vlcPlayer.delegate = self
        vlcPlayer.rate = self.playbackRate
        
        vlcPlayer.play()
        self.isPlaying = true
        self.isBuffering = true
        
        startProgressTracking()
        startTimeoutTimer()
        triggerControls()
    }
    
    private func startTimeoutTimer() {
        timeoutTimer?.invalidate()
        // Allow 30 seconds for connection negotiation in hostile networks
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // If still buffering and no time elapsed, consider it a timeout
            if self.isBuffering && self.currentTime < 1 {
                self.reportError("Connection Timed Out", reason: "Stream failed to start. Check connection or VPN.")
            }
        }
    }
    
    // MARK: - Track Logic
    
    private func loadTracks() {
        // Audio
        if let names = vlcPlayer.audioTrackNames as? [String],
           let indexes = vlcPlayer.audioTrackIndexes as? [Int] {
            self.audioTracks = names
            
            // FIX: Explicitly convert Int32 -> Int for comparison
            let currentIndex = Int(vlcPlayer.currentAudioTrackIndex)
            
            if let found = indexes.firstIndex(of: currentIndex) {
                self.currentAudioIndex = found
            }
        }
        
        // Subtitles
        if let names = vlcPlayer.videoSubTitlesNames as? [String],
           let indexes = vlcPlayer.videoSubTitlesIndexes as? [Int] {
            self.subtitleTracks = names
            
            // FIX: Explicitly convert Int32 -> Int for comparison
            let currentIndex = Int(vlcPlayer.currentVideoSubTitleIndex)
            
            if let found = indexes.firstIndex(of: currentIndex) {
                self.currentSubtitleIndex = found
            }
        }
    }
    
    func setAudioTrack(index: Int) {
        guard index < audioTracks.count,
              let indexes = vlcPlayer.audioTrackIndexes as? [Int] else { return }
        
        let vlcIndex = indexes[index]
        // FIX: Explicitly convert Int -> Int32 for assignment
        vlcPlayer.currentAudioTrackIndex = Int32(vlcIndex)
        self.currentAudioIndex = index
        
        triggerControls(forceShow: true)
    }
    
    func setSubtitleTrack(index: Int) {
        guard index < subtitleTracks.count,
              let indexes = vlcPlayer.videoSubTitlesIndexes as? [Int] else { return }
        
        let vlcIndex = indexes[index]
        // FIX: Explicitly convert Int -> Int32 for assignment
        vlcPlayer.currentVideoSubTitleIndex = Int32(vlcIndex)
        self.currentSubtitleIndex = index
        
        triggerControls(forceShow: true)
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
            
            let meta = try? context.fetch(req).first
            let overview = meta?.overview ?? "No details available."
            let rating = meta?.voteAverage ?? 0.0
            let ratingStr = rating > 0 ? String(format: "%.1f", rating) : ""
            
            let info = TitleNormalizer.parse(rawTitle: title)
            let year = info.year ?? ""
            
            await MainActor.run {
                self.videoOverview = overview
                self.videoRating = ratingStr
                self.videoYear = year
            }
        }
    }
    
    // MARK: - Next Episode Logic
    
    func checkForNextEpisode() {
        guard let repo = repository,
              let current = currentChannel,
              (current.type == "series" || current.type == "series_episode") else { return }
        
        Task.detached {
            let context = repo.container.newBackgroundContext()
            await context.perform {
                if let bgChannel = try? context.existingObject(with: current.objectID) as? Channel {
                    // Try Optimized Database Lookup first (if seriesId is present)
                    if let sid = bgChannel.seriesId {
                        if let next = self.findNextEpisodeDB(context: context, seriesId: sid, season: Int(bgChannel.season), episode: Int(bgChannel.episode)) {
                            let nextID = next.objectID
                            Task { @MainActor in
                                if let mainNext = try? repo.container.viewContext.existingObject(with: nextID) as? Channel {
                                    self.nextEpisode = mainNext
                                    self.canPlayNext = true
                                }
                            }
                            return
                        }
                    }
                    
                    // Fallback to Regex Logic
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
    
    private nonisolated func findNextEpisodeDB(context: NSManagedObjectContext, seriesId: String, season: Int, episode: Int) -> Channel? {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        // Check Next Episode
        req.predicate = NSPredicate(format: "seriesId == %@ AND season == %d AND episode == %d", seriesId, season, episode + 1)
        req.fetchLimit = 1
        if let next = try? context.fetch(req).first { return next }
        
        // Check Next Season (Episode 1)
        req.predicate = NSPredicate(format: "seriesId == %@ AND season == %d AND episode == 1", seriesId, season + 1)
        if let nextSeason = try? context.fetch(req).first { return nextSeason }
        
        return nil
    }
    
    private nonisolated func findNextEpisodeInternal(context: NSManagedObjectContext, current: Channel) -> Channel? {
        let title = current.title
        guard let regex = try? NSRegularExpression(pattern: "(?i)(S)(\\d+)\\s*(E)(\\d+)") else { return nil }
        let nsString = title as NSString
        let results = regex.matches(in: title, range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.first, match.numberOfRanges >= 5 else { return nil }
        
        guard let s = Int(nsString.substring(with: match.range(at: 2))),
              let e = Int(nsString.substring(with: match.range(at: 4))) else { return nil }
        
        if let next = findSpecificEpisode(context: context, playlistUrl: current.playlistUrl, titlePrefix: String(title.prefix(5)), season: s, episode: e + 1) {
            return next
        }
        if let nextSeason = findSpecificEpisode(context: context, playlistUrl: current.playlistUrl, titlePrefix: String(title.prefix(5)), season: s + 1, episode: 1) {
            return nextSeason
        }
        return nil
    }
    
    private nonisolated func findSpecificEpisode(context: NSManagedObjectContext, playlistUrl: String, titlePrefix: String, season: Int, episode: Int) -> Channel? {
        let req = NSFetchRequest<Channel>(entityName: "Channel")
        req.predicate = NSPredicate(format: "playlistUrl == %@ AND title BEGINSWITH[cd] %@", playlistUrl, titlePrefix)
        req.fetchLimit = 500
        
        guard let candidates = try? context.fetch(req) else { return nil }
        let targetS = String(format: "S%02d", season)
        let targetE = String(format: "E%02d", episode)
        
        return candidates.first { ch in
            let t = ch.title.uppercased()
            return t.contains(targetS) && t.contains(targetE)
        }
    }
    
    // MARK: - Auto Play Logic
    
    func triggerAutoPlay() {
        guard canPlayNext else { triggerControls(forceShow: true); return }
        self.showAutoPlay = true
        self.autoPlayCounter = 20
        self.showControls = false
        
        autoPlayTimer?.invalidate()
        autoPlayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.autoPlayCounter > 0 { self.autoPlayCounter -= 1 }
            else { self.confirmAutoPlay() }
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
            NotificationCenter.default.post(name: NSNotification.Name("PlayNextEpisode"), object: next)
        }
    }
    
    // MARK: - VLC Delegate
    
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
                self.timeoutTimer?.invalidate() // Connection success
                
                if let len = player.media?.length, len.intValue > 0 {
                    self.duration = Double(len.intValue) / 1000.0
                }
                
                self.loadTracks() // Load tracks when metadata is ready
                
                if player.rate != self.playbackRate { player.rate = self.playbackRate }
                self.triggerControls()
                
            case .paused:
                self.isPlaying = false
                self.isBuffering = false
                self.triggerControls(forceShow: true)
                
            case .error:
                self.reportError("Playback Error", reason: "Stream failed.")
                
            case .ended:
                self.isPlaying = false
                if self.canPlayNext { self.triggerAutoPlay() }
                else { self.triggerControls(forceShow: true) }
                
            case .stopped:
                self.isPlaying = false
                self.triggerControls(forceShow: true)
                
            default: break
            }
        }
    }
    
    @objc nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in self.updateTimeFromPlayer() }
    }
    
    private func updateTimeFromPlayer() {
        if isScrubbing { return }
        
        let playerTime = Double(vlcPlayer.time.intValue) / 1000.0
        
        if self.duration == 0, let len = vlcPlayer.media?.length, len.intValue > 0 {
            self.duration = Double(len.intValue) / 1000.0
        }
        
        if let commit = seekCommitTime {
            if Date().timeIntervalSince(commit) < 2.0 { return }
            else { self.seekCommitTime = nil; self.targetSeekTime = nil }
        }
        
        self.currentTime = playerTime
    }
    
    // MARK: - Controls
    
    func assignView(_ view: UIView) { vlcPlayer.drawable = view }
    
    func togglePlayPause() {
        if vlcPlayer.isPlaying {
            vlcPlayer.pause()
            self.isPlaying = false
        } else {
            vlcPlayer.play()
            self.isPlaying = true
            withAnimation { self.showMiniDetails = false; self.showTrackSelection = false }
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
        let newTimeMs = max(0, currentMs + deltaMs)
        
        self.currentTime = Double(newTimeMs) / 1000.0
        commitSeek(to: newTimeMs)
        triggerControls(forceShow: true)
    }
    
    func startScrubbing(translation: CGFloat, screenWidth: CGFloat) {
        if duration == 0 {
            if let len = vlcPlayer.media?.length, len.intValue > 0 {
                self.duration = Double(len.intValue) / 1000.0
            }
        }
        guard duration > 0 else { return }
        
        isScrubbing = true
        triggerControls(forceShow: true)
        
        if scrubbingOriginTime == nil { scrubbingOriginTime = currentTime }
        guard let origin = scrubbingOriginTime else { return }
        
        let baseSeekWindow = max(120.0, duration * 0.10)
        let percentage = Double(translation / screenWidth)
        let timeDelta = baseSeekWindow * percentage
        let newTime = max(0, min(origin + timeDelta, duration))
        
        self.currentTime = newTime
    }
    
    func endScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        scrubbingOriginTime = nil
        if currentTime > 0 { commitSeek(to: Int32(currentTime * 1000)) }
    }
    
    private func commitSeek(to ms: Int32) {
        vlcPlayer.time = VLCTime(int: ms)
        targetSeekTime = Double(ms) / 1000.0
        seekCommitTime = Date()
    }
    
    func triggerControls(forceShow: Bool = false) {
        controlHideTimer?.invalidate()
        withAnimation { showControls = true }
        
        if (vlcPlayer.isPlaying || forceShow == false) && !isError && !showAutoPlay {
            controlHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.vlcPlayer.isPlaying && !self.isScrubbing && !self.showMiniDetails && !self.showTrackSelection && !self.showAutoPlay {
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
        saveCurrentProgress()
        progressTimer?.invalidate()
        controlHideTimer?.invalidate()
        autoPlayTimer?.invalidate()
        timeoutTimer?.invalidate() // Clean up timeout
        if vlcPlayer.isPlaying { vlcPlayer.stop() }
        vlcPlayer.delegate = nil
        vlcPlayer.drawable = nil
    }
    
    // MARK: - Helpers
    
    private func startProgressTracking() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateTimeFromPlayer()
            
            if self.vlcPlayer.isPlaying {
                if self.isBuffering { self.isBuffering = false }
                if !self.isPlaying { self.isPlaying = true }
            }
            
            if self.isPlaying && abs(self.currentTime - self.lastSavedTime) > 10 {
                self.saveCurrentProgress()
            }
        }
    }
    
    private func saveCurrentProgress() {
        guard let repo = self.repository, let channel = self.currentChannel else { return }
        let pos = Int64(self.currentTime * 1000)
        let dur = Int64(self.duration * 1000)
        self.lastSavedTime = self.currentTime
        
        if (pos > 10000 && dur > 0) || channel.type == "live" {
            Task { @MainActor in
                repo.saveProgress(url: self.currentUrl, pos: pos, dur: dur)
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
