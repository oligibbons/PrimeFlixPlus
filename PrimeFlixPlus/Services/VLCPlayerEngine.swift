import Foundation
import Combine
import TVVLCKit

/// A robust, SwiftUI-friendly wrapper around VLCMediaPlayer.
/// Includes Watchdog logic, Safe Seeking, Resume support, AV Sync, and Video Settings.
/// OPTIMIZATION UPDATE: Implements Dynamic RAM-Based Buffering and Hardware Decoding Control.
class VLCPlayerEngine: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    
    // MARK: - Published State
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var error: String? = nil
    
    // Tracks & Sync
    @Published var audioTracks: [String] = []
    @Published var currentAudioIndex: Int = 0
    @Published var subtitleTracks: [String] = []
    @Published var currentSubtitleIndex: Int = 0
    
    // Delays (in milliseconds)
    @Published var audioDelay: Int = 0
    @Published var subtitleDelay: Int = 0
    
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
    
    /// Loads media with Dynamic RAM Buffering calculation.
    /// - Parameters:
    ///   - quality: Used to estimate bitrate (e.g., "4K", "1080p").
    func load(url: String, isLive: Bool, quality: String?, startTime: Double = 0) {
        self.error = nil
        self.duration = 0
        self.currentTime = startTime // Optimistic set
        self.isBuffering = true
        self.lastTimeRecorded = -1.0
        
        guard let mediaUrl = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url) else {
            self.error = "Invalid URL"
            return
        }
        
        let media = VLCMedia(url: mediaUrl)
        
        // --- SMART BUFFERING LOGIC ---
        
        // 1. Get User RAM Cap (Default 300MB if not set)
        // This setting ensures we never exceed safe memory limits on the Apple TV.
        let memoryLimitMB = UserDefaults.standard.integer(forKey: "bufferMemoryLimit")
        let limit = memoryLimitMB > 0 ? memoryLimitMB : 300
        
        // 2. Estimate Bitrate (Mbps) based on Quality Tag
        // These are conservative "High Quality" estimates to ensure safety.
        // A 4K Remux might spike to 80-100Mbps, so we use a safe average of 60Mbps.
        let estimatedBitrate: Double
        if let q = quality {
            if q.contains("4K") || q.contains("UHD") {
                estimatedBitrate = 60.0 // 4K Remux average
            } else if q.contains("1080") {
                estimatedBitrate = 15.0 // High quality 1080p
            } else if q.contains("720") {
                estimatedBitrate = 6.0
            } else {
                estimatedBitrate = 4.0 // SD/Unknown
            }
        } else {
            estimatedBitrate = isLive ? 10.0 : 15.0 // Default assumptions
        }
        
        // 3. Calculate Duration Capacity
        // Formula: (MB * 8 bits) / Mbps = Seconds
        // Example: (300MB * 8) / 15Mbps = 160 seconds buffer
        let capacitySeconds = (Double(limit) * 8.0) / estimatedBitrate
        
        // 4. Apply Constraints
        // Live TV needs a floor (3s) to handle jitter, but a ceiling (30s) to avoid huge lag behind live edge.
        // VOD uses the full calculated capacity, capped at 300s (5 mins) to prevent seek issues.
        let finalCacheMs: Int
        if isLive {
            let clamped = min(max(capacitySeconds, 3.0), 30.0)
            finalCacheMs = Int(clamped * 1000)
        } else {
            let clamped = min(capacitySeconds, 300.0)
            finalCacheMs = Int(clamped * 1000)
        }
        
        print("[StreamOptimizer] RAM Cap: \(limit)MB | Quality: \(quality ?? "Unknown") | Bitrate Est: \(estimatedBitrate)Mbps | Buffer: \(finalCacheMs)ms")
        
        // --- HARDWARE SETTINGS ---
        
        // Default to true (Hardware) as it's standard for Apple TV.
        // Disabling this is a "Secret Weapon" for fixing green/glitchy streams.
        let useHardware = UserDefaults.standard.object(forKey: "useHardwareDecoding") as? Bool ?? true
        
        var options: [String: Any] = [
            "network-caching": finalCacheMs,
            "clock-jitter": 0,
            "clock-synchro": 0,
            "http-reconnect": true
        ]
        
        if !useHardware {
            options["avcodec-hw"] = "none"
        }
        
        // Start Time Optimization
        if startTime > 0 {
            options["start-time"] = "\(startTime)"
        }
        
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
        if player.isPlaying { pause() } else { play() }
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
    
    // MARK: - Video Settings (Dynamic)
    
    func setDeinterlace(_ enabled: Bool) {
        // "blend" is a safe, performant deinterlacing filter for tvOS
        player.setDeinterlaceFilter(enabled ? "blend" : nil)
    }
    
    func setAspectRatio(_ ratio: String) {
        if ratio == "Default" {
            player.videoAspectRatio = nil
        } else if ratio == "Fill" {
            // Force 16:9 to fill typical TV screens
            player.videoAspectRatio = UnsafeMutablePointer<Int8>(mutating: ("16:9" as NSString).utf8String)
        } else {
            // Custom ratios
            player.videoAspectRatio = UnsafeMutablePointer<Int8>(mutating: (ratio as NSString).utf8String)
        }
    }
    
    // MARK: - Synchronization
    
    func setAudioDelay(_ ms: Int) {
        self.audioDelay = ms
        player.currentAudioPlaybackDelay = Int(ms * 1000)
    }
    
    func setSubtitleDelay(_ ms: Int) {
        self.subtitleDelay = ms
        player.currentVideoSubTitleDelay = Int(ms * 1000)
    }
    
    // MARK: - Safe Seeking
    
    func seek(to time: Double) {
        guard player.media != nil, player.state != .error, player.state != .stopped else { return }
        
        isSeeking = true
        let vlcTime = VLCTime(int: Int32(time * 1000))
        player.time = vlcTime
        self.currentTime = time
        
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
            
            if self.duration <= 0.1, let len = p.media?.length, len.intValue > 0 {
                self.duration = Double(len.intValue) / 1000.0
            }
            
            switch p.state {
            case .buffering:
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
            default: break
            }
        }
    }
    
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        if isSeeking { return }
        
        Task { @MainActor in
            let time = Double(player.time.intValue) / 1000.0
            self.currentTime = time
            
            if self.isBuffering && time > (self.lastTimeRecorded + 0.5) {
                self.isBuffering = false
            }
            self.lastTimeRecorded = time
        }
    }
    
    private func startTimers() {
        progressTimer?.invalidate()
        watchdogTimer?.invalidate()
        
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.player.isPlaying && !self.isSeeking {
                let t = Double(self.player.time.intValue) / 1000.0
                if t > 0 {
                    Task { @MainActor in self.currentTime = t }
                }
            }
        }
        
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.isBuffering && self.player.isPlaying && self.player.state == .playing {
                    self.isBuffering = false
                }
            }
        }
    }
}
