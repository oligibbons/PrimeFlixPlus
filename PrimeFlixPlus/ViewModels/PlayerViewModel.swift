

import Foundation
import Combine
import SwiftUI
import TVVLCKit

@MainActor // Ensure the whole class runs on Main Actor
class PlayerViewModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    
    // VLC Engine
    let vlcPlayer = VLCMediaPlayer()
    
    // UI State
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = true
    @Published var isError: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showControls: Bool = false
    
    // Metadata
    @Published var videoTitle: String = ""
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var currentUrl: String = ""
    
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
        
        setupVLC(url: channel.url)
    }
    
    // MARK: - VLC Setup
    
    private func setupVLC(url: String) {
        // 1. Basic percent encoding for spaces, but keep structure intact
        guard let mediaUrl = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url) else {
            reportError("Invalid URL", reason: url)
            return
        }
        
        // 2. Create Media Object
        let media = VLCMedia(url: mediaUrl)
        
        // 3. Network Optimizations
        // Increase caching to 3000ms (3s) to handle slow IPTV responses without stuttering
        media.addOptions([
            "network-caching": 3000,
            "clock-jitter": 0,
            "clock-synchro": 0
        ])
        
        vlcPlayer.media = media
        vlcPlayer.delegate = self
        
        // 4. Start Playback
        vlcPlayer.play()
        self.isPlaying = true
        self.isBuffering = true
        
        startProgressTracking()
        triggerControls() // Show controls immediately on start
    }
    
    // MARK: - VLC Delegate Methods
    
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
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
            default:
                break
            }
        }
    }
    
    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            
            // OPTIMIZATION: Only update if the difference is significant to avoid
            // fighting with the optimistic scrubbing updates.
            let newTime = Double(player.time.intValue) / 1000.0
            if abs(newTime - self.currentTime) > 0.5 || player.isPlaying {
                self.currentTime = newTime
            }
        }
    }
    
    // MARK: - Controls
    
    func assignView(_ view: UIView) {
        vlcPlayer.drawable = view
    }
    
    func togglePlayPause() {
        if vlcPlayer.isPlaying {
            vlcPlayer.pause()
        } else {
            vlcPlayer.play()
        }
        triggerControls(forceShow: true)
    }
    
    // MARK: - Seeking Logic
    
    func seekForward(seconds: Int = 10) {
        seek(by: seconds)
    }
    
    func seekBackward(seconds: Int = 10) {
        seek(by: -seconds)
    }
    
    private func seek(by seconds: Int) {
        guard vlcPlayer.isSeekable else { return }
        
        // 1. Calculate new time
        let currentMs = Int32(self.currentTime * 1000) // Use local source of truth for smoothness
        let deltaMs = Int32(seconds * 1000)
        let newTimeMs = currentMs + deltaMs
        
        // 2. Bounds checking
        let maxTimeMs = Int32(duration * 1000)
        let safeTimeMs = max(0, min(newTimeMs, maxTimeMs))
        
        // 3. Optimistic UI Update (CRITICAL FIX)
        // We update the UI immediately so the user sees the slider move.
        // We don't wait for VLC to report back.
        self.currentTime = Double(safeTimeMs) / 1000.0
        
        // 4. Apply Seek to Player
        vlcPlayer.time = VLCTime(int: safeTimeMs)
        
        // 5. Feedback
        triggerControls(forceShow: true)
    }
    
    // MARK: - UI Management
    
    func triggerControls(forceShow: Bool = false) {
        controlHideTimer?.invalidate()
        withAnimation { showControls = true }
        
        if (vlcPlayer.isPlaying || forceShow == false) && !isError {
            controlHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.vlcPlayer.isPlaying {
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
        if vlcPlayer.isPlaying { vlcPlayer.stop() }
        vlcPlayer.delegate = nil
        vlcPlayer.drawable = nil
    }
    
    // MARK: - Helpers
    
    private func startProgressTracking() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Failsafe: If time is moving, kill the spinner (even if delegate missed the event)
            // Only do this if we are actually playing to avoid hiding it during seek buffering
            if self.vlcPlayer.isPlaying && self.currentTime > 0 && self.isBuffering {
                Task { @MainActor in self.isBuffering = false }
            }
            
            // Save Progress (every 5s)
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
