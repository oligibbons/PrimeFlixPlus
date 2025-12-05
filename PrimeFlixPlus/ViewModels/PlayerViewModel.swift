// oligibbons/primeflixplus/PrimeFlixPlus-7315d01e01d1e889e041552206b1fb283d2eeb2d/PrimeFlixPlus/ViewModels/PlayerViewModel.swift

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
    private var controlHideTimer: Timer? // NEW: Use Timer for controls hiding
    
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
    
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification!) {
        Task { @MainActor in
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            
            switch player.state {
            case .buffering:
                self.isBuffering = true
                self.triggerControls() // Keep controls visible during buffer
            case .playing:
                // When we start playing, stop buffering and enable playback state
                self.isBuffering = false
                self.isPlaying = true
                self.isError = false
                
                // Update Duration
                if let len = player.media?.length, len.intValue > 0 {
                    self.duration = Double(len.intValue) / 1000.0
                }
                self.triggerControls() // Re-hide controls after playing starts
            case .paused: // NEW: Handle paused state correctly
                self.isPlaying = false
                self.isBuffering = false
                self.triggerControls(forceShow: true) // Keep controls visible when paused
            case .error:
                self.reportError("Playback Error", reason: "Stream failed to load.")
            case .ended, .stopped:
                self.isPlaying = false
                self.isBuffering = false // Also clear buffering on stop/end
                self.triggerControls(forceShow: true)
            default:
                self.isBuffering = false // For any other non-buffering state, dismiss spinner
                break
            }
        }
    }
    
    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification!) {
        Task { @MainActor in
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            let time = player.time
            self.currentTime = Double(time.intValue) / 1000.0
        }
    }
    
    // MARK: - Controls
    
    func assignView(_ view: UIView) {
        // Bind the UIView to VLC's drawable
        vlcPlayer.drawable = view
    }
    
    func togglePlayPause() {
        if vlcPlayer.isPlaying {
            vlcPlayer.pause()
            // State will be updated via delegate call, which is safer
        } else {
            vlcPlayer.play()
            // State will be updated via delegate call, which is safer
        }
        triggerControls(forceShow: true)
    }
    
    // UPDATED: Controls logic now uses Timer, and can be forced to stay visible
    func triggerControls(forceShow: Bool = false) {
        controlHideTimer?.invalidate() // Reset timer on any interaction
        
        withAnimation { showControls = true }
        
        // Only set the timer to hide if we're not explicitly forced to stay visible (e.g. paused)
        if vlcPlayer.isPlaying && !forceShow {
            controlHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                withAnimation { self.showControls = false }
            }
        } else if !vlcPlayer.isPlaying {
            // If paused or ended, keep controls visible indefinitely
            withAnimation { showControls = true }
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
        controlHideTimer?.invalidate() // NEW: Invalidate controls timer
        if vlcPlayer.isPlaying { vlcPlayer.stop() }
        vlcPlayer.delegate = nil
        vlcPlayer.drawable = nil
    }
    
    // MARK: - Helpers
    
    private func startProgressTracking() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let repo = self.repository, let channel = self.currentChannel else { return }
            
            let pos = Int64(self.currentTime * 1000)
            let dur = Int64(self.duration * 1000)
            
            // Fix: VLC state can sometimes lag, check if it's playing via VLC state
            let isVLCPlaying = self.vlcPlayer.isPlaying || self.vlcPlayer.state == .playing
            
            if (pos > 10000 && dur > 0 && isVLCPlaying) || channel.type == "live" {
                Task { @MainActor in
                    repo.saveProgress(url: self.currentUrl, pos: pos, dur: dur)
                }
            }
        }
    }
    
    private func reportError(_ title: String, reason: String) {
        self.isError = true
        self.errorMessage = "\(title): \(reason)"
        self.isBuffering = false
    }
}
