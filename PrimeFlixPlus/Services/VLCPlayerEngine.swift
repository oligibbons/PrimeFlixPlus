import Foundation
import Combine
import TVVLCKit

/// A SwiftUI-friendly wrapper around VLCMediaPlayer.
/// Converts imperative delegate callbacks into reactive @Published properties.
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
    private var isSeeking: Bool = false
    
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
    }
    
    // MARK: - Playback Control
    
    func load(url: String, isLive: Bool, is4K: Bool) {
        // Reset State
        self.error = nil
        self.duration = 0
        self.currentTime = 0
        self.isBuffering = true
        
        guard let mediaUrl = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url) else {
            self.error = "Invalid URL"
            return
        }
        
        let media = VLCMedia(url: mediaUrl)
        
        // Optimize Caching based on content type
        let cacheSize = isLive ? 3000 : (is4K ? 10000 : 5000)
        let options: [String: Any] = [
            "network-caching": cacheSize,
            "clock-jitter": 0,
            "clock-synchro": 0,
            "http-reconnect": true
        ]
        media.addOptions(options)
        
        player.media = media
        player.play()
        
        startProgressTracking()
    }
    
    func play() {
        player.play()
        self.isPlaying = true
    }
    
    func pause() {
        player.pause()
        self.isPlaying = false
    }
    
    func stop() {
        player.stop()
        self.isPlaying = false
        progressTimer?.invalidate()
    }
    
    func setRate(_ rate: Float) {
        player.rate = rate
    }
    
    // MARK: - Seeking
    
    /// Seeks to a specific time in seconds.
    func seek(to time: Double) {
        guard player.isSeekable else { return }
        isSeeking = true
        
        let vlcTime = VLCTime(int: Int32(time * 1000))
        player.time = vlcTime
        
        // Optimistic UI update
        self.currentTime = time
        
        // Release lock after small delay to let VLC catch up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isSeeking = false
        }
    }
    
    // MARK: - Track Management
    
    func refreshTracks() {
        if let names = player.audioTrackNames as? [String],
           let indexes = player.audioTrackIndexes as? [Int] {
            self.audioTracks = names
            // Map VLC internal ID back to our array index
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
        // Ensure UI updates happen on Main Thread
        Task { @MainActor in
            guard let p = aNotification.object as? VLCMediaPlayer else { return }
            
            switch p.state {
            case .buffering:
                self.isBuffering = true
            case .playing:
                self.isBuffering = false
                self.isPlaying = true
                self.refreshTracks()
                
                // Duration Check
                if self.duration == 0, let len = p.media?.length, len.intValue > 0 {
                    self.duration = Double(len.intValue) / 1000.0
                }
            case .paused:
                self.isPlaying = false
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
        if isSeeking { return }
        
        Task { @MainActor in
            let time = Double(player.time.intValue) / 1000.0
            self.currentTime = time
        }
    }
    
    private func startProgressTracking() {
        // Fallback timer in case VLC delegate misses updates (common in tvOS)
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.player.isPlaying && !self.isSeeking {
                let t = Double(self.player.time.intValue) / 1000.0
                if t > 0 {
                    Task { @MainActor in self.currentTime = t }
                }
            }
        }
    }
}
