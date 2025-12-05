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
    
    // Scrubbing State (New)
    @Published var isScrubbing: Bool = false
    
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
        
        vlcPlayer.play()
        self.isPlaying = true
        self.isBuffering = true
        
        startProgressTracking()
        triggerControls()
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
            // Don't update time if user is actively scrubbing
            guard !self.isScrubbing else { return }
            
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            let time = player.time
            self.currentTime = Double(time.intValue) / 1000.0
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
        vlcPlayer.time = VLCTime(int: safeTimeMs)
        triggerControls(forceShow: true)
    }
    
    // MARK: - Continuous Scrubbing (Drag)
    
    func startScrubbing(translation: CGFloat, screenWidth: CGFloat) {
        isScrubbing = true
        triggerControls(forceShow: true)
        
        // Calculate scrubbing sensitivity (e.g., full swipe width = 2 minutes)
        let sensitivity: Double = 120.0 // seconds
        let percentage = Double(translation / screenWidth)
        let timeDelta = sensitivity * percentage
        
        var newTime = currentTime + timeDelta
        newTime = max(0, min(newTime, duration))
        
        self.currentTime = newTime
    }
    
    func endScrubbing() {
        isScrubbing = false
        let ms = Int32(currentTime * 1000)
        vlcPlayer.time = VLCTime(int: ms)
    }
    
    // MARK: - UI Management
    
    func triggerControls(forceShow: Bool = false) {
        controlHideTimer?.invalidate()
        withAnimation { showControls = true }
        
        if (vlcPlayer.isPlaying || forceShow == false) && !isError {
            controlHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.vlcPlayer.isPlaying && !self.isScrubbing {
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
            
            if self.currentTime > 0 && self.isBuffering {
                Task { @MainActor in self.isBuffering = false }
            }
            
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
