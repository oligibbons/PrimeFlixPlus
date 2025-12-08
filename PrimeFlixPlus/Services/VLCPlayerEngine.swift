import Foundation
import Combine
import TVVLCKit

/// A robust, SwiftUI-friendly wrapper around VLCMediaPlayer.
/// Includes "Watchdog" logic and "Safe Seek" to prevent crashes.
class VLCPlayerEngine: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    
    // MARK: - Published State
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var error: String? = nil
    
    // Tracks
    @Published var audioTracks: [String] = []
    @Published var currentAudioIndex: Int = 0
    @Published var subtitleTracks: [String] = []
    @Published var currentSubtitleIndex: Int = 0
    
    // MARK: - Internal Properties
    private let player = VLCMediaPlayer()
    private var progressTimer: Timer?
    private var watchdogTimer: Timer?
    private var isSeeking: Bool = false
    private var lastTimeRecorded: Double = -1.0
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
        player.delegate = self
    }
    
    func attach(to view: UIView) {
        player.drawable = view
    }
    
    func cleanup() {
        stop()
        player.delegate = nil
        player.drawable = nil
        progressTimer?.invalidate()
        watchdogTimer?.invalidate()
    }
    
    // MARK: - Playback Control
    
    func load(url: String, isLive: Bool, is4K: Bool) {
        self.error = nil
        self.duration = 0
        self.currentTime = 0
        self.isBuffering = true
        self.lastTimeRecorded = -1.0
        
        guard let mediaUrl = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url) else {
            self.error = "Invalid URL"
            return
        }
        
        let media = VLCMedia(url: mediaUrl)
        
        // Optimized Caching for tvOS stability
        let cacheSize = isLive ? 5000 : (is4K ? 15000 : 4000)
        let options: [String: Any] = [
            "network-caching": cacheSize,
            "clock-jitter": 0,
            "clock-synchro": 0,
            "http-reconnect": true
        ]
        media.addOptions(options)
        
        player.media = media
        player.play()
        
        startTimers()
    }
    
    func play() {
        if !player.isPlaying {
            player.play()
            self.isPlaying = true
        }
    }
    
    func pause() {
        if player.isPlaying {
            player.pause()
            self.isPlaying = false
        }
    }
    
    func togglePlayPause() {
        if player.isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func stop() {
        player.stop()
        self.isPlaying = false
        self.isBuffering = false
        progressTimer?.invalidate()
        watchdogTimer?.invalidate()
    }
    
    func setRate(_ rate: Float) {
        player.rate = rate
    }
    
    // MARK: - Safe Seeking
    
    func seek(to time: Double) {
        // 1. Safety Check: Ensure media exists and is valid
        guard player.media != nil, player.state != .error, player.state != .stopped else {
            print("⚠️ Seek Ignored: Player in invalid state.")
            return
        }
        
        // 2. Lock Updates
        isSeeking = true
        
        // 3. Perform Seek
        let vlcTime = VLCTime(int: Int32(time * 1000))
        player.time = vlcTime
        
        // 4. Paused Scrub Fix: Force a frame update if paused
        if !player.isPlaying {
            // VLC trick: sometimes need to 'play' momentarily to render the new frame
            // usually not strictly required if just updating time, but good for "Live Scrub" preview.
            // For now, we trust the player to update the frame buffer.
        }
        
        // Optimistic UI update
        self.currentTime = time
        
        // 5. Release Lock with Delay (Allow engine to catch up)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.isSeeking = false
        }
    }
    
    // MARK: - Track Management
    
    func refreshTracks() {
        if let names = player.audioTrackNames as? [String],
           let indexes = player.audioTrackIndexes as? [Int] {
            self.audioTracks = names
            let internalId = Int(player.currentAudioTrackIndex)
            if let found = indexes.firstIndex(of: internalId) { self.currentAudioIndex = found }
        }
        
        if let names = player.videoSubTitlesNames as? [String],
           let indexes = player.videoSubTitlesIndexes as? [Int] {
            self.subtitleTracks = names
            let internalId = Int(player.currentVideoSubTitleIndex)
            if let found = indexes.firstIndex(of: internalId) { self.currentSubtitleIndex = found }
        }
    }
    
    func setAudioTrack(_ index: Int) {
        guard let indexes = player.audioTrackIndexes as? [Int], index < indexes.count else { return }
        player.currentAudioTrackIndex = Int32(indexes[index])
        self.currentAudioIndex = index
    }
    
    func setSubtitleTrack(_ index: Int) {
        guard let indexes = player.videoSubTitlesIndexes as? [Int], index < indexes.count else { return }
        player.currentVideoSubTitleIndex = Int32(indexes[index])
        self.currentSubtitleIndex = index
    }
    
    // MARK: - Delegate Handling
    
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let p = aNotification.object as? VLCMediaPlayer else { return }
            
            // Check for valid duration update
            if self.duration <= 0.1, let len = p.media?.length, len.intValue > 0 {
                self.duration = Double(len.intValue) / 1000.0
            }
            
            switch p.state {
            case .buffering:
                // Only show buffering if NOT scrubbing and NOT seeking
                if !self.isSeeking && abs(self.currentTime - self.lastTimeRecorded) < 1.0 {
                    self.isBuffering = true
                }
            case .playing:
                self.isBuffering = false
                self.isPlaying = true
                self.refreshTracks()
            case .paused:
                self.isPlaying = false
                self.isBuffering = false
            case .ended:
                self.isPlaying = false
                self.isBuffering = false
            case .error:
                self.isBuffering = false
                self.error = "Playback Stream Error"
            default:
                break
            }
        }
    }
    
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        // STRICT BLOCK: Do not update time while seeking
        if isSeeking { return }
        
        Task { @MainActor in
            let time = Double(player.time.intValue) / 1000.0
            self.currentTime = time
            
            // Watchdog: If time advanced, kill buffering
            if self.isBuffering && time > (self.lastTimeRecorded + 0.5) {
                self.isBuffering = false
            }
            self.lastTimeRecorded = time
        }
    }
    
    private func startTimers() {
        progressTimer?.invalidate()
        watchdogTimer?.invalidate()
        
        // Progress Timer
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.player.isPlaying && !self.isSeeking {
                let t = Double(self.player.time.intValue) / 1000.0
                if t > 0 {
                    Task { @MainActor in self.currentTime = t }
                }
            }
        }
        
        // Watchdog Timer
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.isBuffering && self.player.isPlaying {
                    // Force re-check
                    if self.player.state == .playing {
                        self.isBuffering = false
                    }
                }
            }
        }
    }
}
