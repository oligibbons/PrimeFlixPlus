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
    
    // NEW: In-Player Version Selection
    @Published var showVersionSelection: Bool = false
    @Published var alternativeVersions: [Channel] = []
    
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
    @Published var qualityBadge: String = "HD"
    
    // MARK: - Extended Metadata
    @Published var videoOverview: String = ""
    @Published var videoYear: String = ""
    @Published var videoRating: String = ""
    @Published var posterImage: URL? = nil
    
    // MARK: - Next Episode Logic
    @Published var nextEpisode: Channel? = nil
    @Published var canPlayNext: Bool = false
    
    // MARK: - Favorites
    @Published var isFavorite: Bool = false
    private var currentChannel: Channel?
    
    // MARK: - Dependencies
    private var repository: PrimeFlixRepository?
    private let tmdbClient = TmdbClient()
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
        self.qualityBadge = channel.quality ?? "HD"
        
        // Load Alternatives (Versions)
        if let repo = repository {
            Task {
                let versions = repo.getVersions(for: channel)
                await MainActor.run {
                    self.alternativeVersions = versions.filter { $0.url != channel.url }
                }
            }
        }
        
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
        
        // Smart Buffering
        let cacheSize: Int
        if type == "live" {
            cacheSize = 3000
        } else if let q = currentChannel?.quality, q.contains("4K") {
            cacheSize = 10000 // 10s for 4K
        } else {
            cacheSize = 5000 // 5s standard
        }
        
        let options: [String: Any] = [
            "network-caching": cacheSize,
            "clock-jitter": 0,
            "clock-synchro": 0,
            "http-reconnect": true,
            ":http-reconnect": true,
            "http-user-agent": "okhttp/3.12.1", // Bypass blocks
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
    
    func switchVersion(_ newChannel: Channel) {
        // Save progress of current
        saveCurrentProgress()
        
        // Swap channel reference
        self.currentChannel = newChannel
        self.currentUrl = newChannel.url
        self.videoTitle = newChannel.title
        self.qualityBadge = newChannel.quality ?? "HD"
        
        // Restart VLC with new URL
        vlcPlayer.stop()
        setupVLC(url: newChannel.url, type: newChannel.type)
        
        // UI Feedback
        self.showVersionSelection = false
        triggerControls(forceShow: true)
    }
    
    private func startTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.isBuffering && self.currentTime < 1 {
                self.reportError("Connection Timed Out", reason: "Stream failed to start. Check connection.")
            }
        }
    }
    
    // MARK: - Track Logic
    
    private func loadTracks() {
        if let names = vlcPlayer.audioTrackNames as? [String],
           let indexes = vlcPlayer.audioTrackIndexes as? [Int] {
            self.audioTracks = names
            let current = Int(vlcPlayer.currentAudioTrackIndex)
            if let found = indexes.firstIndex(of: current) { self.currentAudioIndex = found }
        }
        
        if let names = vlcPlayer.videoSubTitlesNames as? [String],
           let indexes = vlcPlayer.videoSubTitlesIndexes as? [Int] {
            self.subtitleTracks = names
            let current = Int(vlcPlayer.currentVideoSubTitleIndex)
            if let found = indexes.firstIndex(of: current) { self.currentSubtitleIndex = found }
        }
    }
    
    func setAudioTrack(index: Int) {
        guard index < audioTracks.count, let indexes = vlcPlayer.audioTrackIndexes as? [Int] else { return }
        vlcPlayer.currentAudioTrackIndex = Int32(indexes[index])
        self.currentAudioIndex = index
        triggerControls(forceShow: true)
    }
    
    func setSubtitleTrack(index: Int) {
        guard index < subtitleTracks.count, let indexes = vlcPlayer.videoSubTitlesIndexes as? [Int] else { return }
        vlcPlayer.currentVideoSubTitleIndex = Int32(indexes[index])
        self.currentSubtitleIndex = index
        triggerControls(forceShow: true)
    }
    
    // MARK: - Metadata Fetching (Smart Match)
    
    private func fetchExtendedMetadata() {
        guard let channel = currentChannel else { return }
        // 1. Prefer Cover from Channel (Pre-calculated)
        if let cover = channel.cover, let url = URL(string: cover) {
            self.posterImage = url
        }
        
        let title = channel.canonicalTitle ?? channel.title
        
        Task.detached {
            // 2. Fetch TMDB Data using Fuzzy Logic (Matches DetailsViewModel)
            let info = TitleNormalizer.parse(rawTitle: title)
            let query = info.normalizedTitle
            
            do {
                if channel.type == "series" || channel.type == "series_episode" {
                    let results = try await self.tmdbClient.searchTv(query: query, year: info.year)
                    if let best = self.findBestMatch(results: results, targetTitle: query) {
                        let details = try await self.tmdbClient.getTvDetails(id: best.id)
                        await MainActor.run {
                            self.updateMetadata(from: details)
                        }
                    }
                } else {
                    let results = try await self.tmdbClient.searchMovie(query: query, year: info.year)
                    if let best = self.findBestMatch(results: results, targetTitle: query) {
                        let details = try await self.tmdbClient.getMovieDetails(id: best.id)
                        await MainActor.run {
                            self.updateMetadata(from: details)
                        }
                    }
                }
            } catch {
                print("Player Metadata Fetch Failed: \(error)")
            }
        }
    }
    
    private func updateMetadata(from details: TmdbDetails) {
        self.videoOverview = details.overview ?? ""
        self.videoRating = details.voteAverage.map { String(format: "%.1f", $0) } ?? ""
        self.videoYear = details.displayDate?.prefix(4).map(String.init) ?? ""
        if let path = details.posterPath {
            self.posterImage = URL(string: "https://image.tmdb.org/t/p/w500\(path)")
        }
    }
    
    // Reused Fuzzy Matcher
    private nonisolated func findBestMatch<T: Identifiable>(results: [T], targetTitle: String) -> T? {
        let target = targetTitle.lowercased()
        return results.first { result in
            var title = ""
            if let m = result as? TmdbMovieResult { title = m.title }
            if let s = result as? TmdbTvResult { title = s.name }
            let t = title.lowercased()
            return t == target || t.contains(target) || target.contains(t)
        }
    }
    
    // MARK: - Next Episode Logic
    
    func checkForNextEpisode() {
        guard let repo = repository, let current = currentChannel,
              (current.type == "series" || current.type == "series_episode") else { return }
        
        // This now leverages the fixed ChannelRepository logic
        Task.detached {
            let context = repo.container.newBackgroundContext()
            await context.perform {
                if let bgChannel = try? context.existingObject(with: current.objectID) as? Channel {
                    // Optimized repository lookup
                    let bgRepo = ChannelRepository(context: context)
                    // We can use a simplified internal finder or rely on the Series ID logic directly
                    if let next = self.findNextInternal(context: context, current: bgChannel) {
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
    
    private nonisolated func findNextInternal(context: NSManagedObjectContext, current: Channel) -> Channel? {
        // 1. Strict Series ID (Best)
        if let sid = current.seriesId, sid != "0" {
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            req.predicate = NSPredicate(format: "seriesId == %@ AND season == %d AND episode == %d", sid, current.season, current.episode + 1)
            req.fetchLimit = 1
            if let next = try? context.fetch(req).first { return next }
        }
        
        // 2. Fallback: Title Regex
        let raw = current.title
        let (s, e) = ChannelStruct.parseSeasonEpisode(from: raw)
        if s > 0 || e > 0 {
            let req = NSFetchRequest<Channel>(entityName: "Channel")
            // Try to find same playlist, same series title prefix, next episode
            let info = TitleNormalizer.parse(rawTitle: raw)
            let prefix = String(info.normalizedTitle.prefix(5))
            let sStr = String(format: "%02d", s)
            let eStr = String(format: "%02d", e + 1)
            
            req.predicate = NSPredicate(format: "playlistUrl == %@ AND title BEGINSWITH[cd] %@ AND (title CONTAINS 'S\(sStr)' OR title CONTAINS 'S\(s)') AND (title CONTAINS 'E\(eStr)' OR title CONTAINS 'E\(e+1)')", current.playlistUrl, prefix)
            req.fetchLimit = 1
            return try? context.fetch(req).first
        }
        return nil
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
                self.timeoutTimer?.invalidate()
                if let len = player.media?.length, len.intValue > 0 { self.duration = Double(len.intValue) / 1000.0 }
                self.loadTracks()
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
            withAnimation { self.showMiniDetails = false; self.showTrackSelection = false; self.showVersionSelection = false }
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
            if let len = vlcPlayer.media?.length, len.intValue > 0 { self.duration = Double(len.intValue) / 1000.0 }
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
                if self.vlcPlayer.isPlaying && !self.isScrubbing && !self.showMiniDetails && !self.showTrackSelection && !self.showVersionSelection && !self.showAutoPlay {
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
        timeoutTimer?.invalidate()
        if vlcPlayer.isPlaying { vlcPlayer.stop() }
        vlcPlayer.delegate = nil
        vlcPlayer.drawable = nil
    }
    
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
            Task { @MainActor in repo.saveProgress(url: self.currentUrl, pos: pos, dur: dur) }
        }
    }
    
    private func reportError(_ title: String, reason: String) {
        self.isError = true
        self.errorMessage = "\(title): \(reason)"
        self.isBuffering = false
        triggerControls(forceShow: true)
    }
}
