import Foundation
import AVKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
class PlayerViewModel: NSObject, ObservableObject, AVAssetResourceLoaderDelegate {
    
    // UI State
    @Published var player: AVPlayer?
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var isError: Bool = false
    @Published var errorMessage: String? = nil
    
    // Metadata
    @Published var videoTitle: String = ""
    @Published var currentUrl: String = ""
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var showControls: Bool = false
    
    // Favorites
    @Published var isFavorite: Bool = false
    private var currentChannel: Channel?
    
    // Dependencies
    private var repository: PrimeFlixRepository?
    private var timeObserver: Any?
    private var itemObservers: Set<AnyCancellable> = []
    private var progressTimer: Timer?
    
    // MARK: - Configuration
    
    func configure(repository: PrimeFlixRepository, channel: Channel) {
        self.repository = repository
        self.currentChannel = channel
        self.videoTitle = channel.title
        self.isFavorite = channel.isFavorite
        
        // 1. Activate Audio Session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Audio Session Error: \(error)")
        }
        
        // 2. NUCLEAR URL SANITIZATION
        // We pass the channel type to apply specific rules (Live -> m3u8, VOD -> mp4)
        guard let sanitizedUrl = nuclearSanitize(url: channel.url, type: channel.type) else {
            reportError("Invalid URL", reason: "Could not parse: \(channel.url)")
            return
        }
        
        self.currentUrl = sanitizedUrl
        print("▶️ Attempting playback (Nuclear Fix): \(sanitizedUrl)")
        
        setupPlayer(url: sanitizedUrl)
    }
    
    // MARK: - Actions
    
    func toggleFavorite() {
        guard let channel = currentChannel, let repo = repository else { return }
        repo.toggleFavorite(channel)
        self.isFavorite.toggle()
        self.triggerControls()
    }
    
    // MARK: - The "Nuclear" Sanitizer
    
    private func nuclearSanitize(url: String, type: String) -> String? {
        var cleanUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Fix Protocol Mess
        if cleanUrl.hasPrefix("http:/") && !cleanUrl.hasPrefix("http://") {
            cleanUrl = cleanUrl.replacingOccurrences(of: "http:/", with: "http://")
        }
        
        // 2. Deconstruct URL to handle Credentials securely
        // Many IPTV providers have issues if special chars in user/pass aren't encoded,
        // OR if they ARE encoded double. We try to reset them.
        
        guard var components = URLComponents(string: cleanUrl.replacingOccurrences(of: " ", with: "%20")) else {
            return cleanUrl // Fallback
        }
        
        // Ensure Scheme
        if components.scheme == nil { components.scheme = "http" }
        
        // 3. FORCE FORMAT COMPATIBILITY (The Critical Fix)
        // tvOS hates .ts for live streams (instability) and .mkv for VOD (unsupported).
        
        if type == "live" {
            // Live TV: FORCE HLS (.m3u8)
            // Most Xtream codes servers support changing the extension to transcode on the fly.
            if components.path.hasSuffix(".ts") {
                let newPath = String(components.path.dropLast(3)) + ".m3u8"
                components.path = newPath
            } else if !components.path.hasSuffix(".m3u8") {
                // If no extension, append it
                components.path += ".m3u8"
            }
        } else {
            // VOD (Movies/Series): FORCE MP4
            // We swap .mkv or .avi to .mp4 to request a compatible stream
            if components.path.hasSuffix(".mkv") {
                let newPath = String(components.path.dropLast(4)) + ".mp4"
                components.path = newPath
            } else if components.path.hasSuffix(".avi") {
                let newPath = String(components.path.dropLast(4)) + ".mp4"
                components.path = newPath
            }
        }
        
        return components.string
    }
    
    // MARK: - Player Setup
    
    private func setupPlayer(url: String) {
        guard let streamUrl = URL(string: url) else {
            reportError("Malformed URL", reason: url)
            return
        }
        
        // 3. ASSET CREATION with SPOOFED HEADERS
        // We mimic IPTV Smarters Pro, which is widely whitelisted by providers.
        let headers: [String: Any] = [
            "User-Agent": "IPTVSmartersPro/1.1.1 (iPad; iOS 15.4; Scale/2.00)"
        ]
        
        let asset = AVURLAsset(url: streamUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        
        // 4. SSL BYPASS (Delegate)
        asset.resourceLoader.setDelegate(self, queue: DispatchQueue.main)
        
        let item = AVPlayerItem(asset: asset)
        
        // Preferences for stability
        item.preferredForwardBufferDuration = 10.0 // Buffer ahead 10s
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        
        // 5. OBSERVERS
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleStatusChange(status, item: item)
            }
            .store(in: &itemObservers)
        
        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keepUp in
                self?.isBuffering = !keepUp
            }
            .store(in: &itemObservers)
        
        item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] empty in
                if empty { self?.isBuffering = true }
            }
            .store(in: &itemObservers)
        
        // 6. INITIALIZE PLAYER
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        
        // Disable "ActionAtItemEnd" logic for live streams to prevent freezing
        if currentChannel?.type == "live" {
            player.automaticallyWaitsToMinimizeStalling = true
        }
        
        self.player = player
        
        // Time Observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
        
        player.play()
        self.isPlaying = true
        startProgressTracking()
    }
    
    // MARK: - SSL Bypass (AVAssetResourceLoaderDelegate)
    
    nonisolated func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForResponseTo authenticationChallenge: URLAuthenticationChallenge) -> Bool {
        // Always trust the server. Essential for many IPTV providers with self-signed certs.
        if let trust = authenticationChallenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: trust)
            authenticationChallenge.sender?.use(credential, for: authenticationChallenge)
            return true
        }
        return false
    }
    
    // MARK: - Cleanup & Logic
    
    private func handleStatusChange(_ status: AVPlayerItem.Status, item: AVPlayerItem) {
        switch status {
        case .readyToPlay:
            print("✅ Player Ready. Duration: \(item.duration.seconds)")
            self.isError = false
            self.isBuffering = false
            if !item.duration.seconds.isNaN {
                self.duration = item.duration.seconds
            }
            
        case .failed:
            if let error = item.error as NSError? {
                let desc = error.localizedDescription
                let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
                let underlyingReason = underlying?.localizedDescription ?? ""
                print("❌ Player Failed: \(desc) | \(underlyingReason)")
                
                // Retry Logic?
                // For now, just report.
                reportError("Playback Failed", reason: "\(desc). \(underlyingReason)")
            } else {
                reportError("Playback Failed", reason: "Unknown Error")
            }
            
        case .unknown:
            break
        @unknown default:
            break
        }
    }
    
    func cleanup() {
        print("🛑 Cleaning up Player")
        progressTimer?.invalidate()
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        itemObservers.removeAll()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        if player.rate != 0 {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        triggerControls()
    }
    
    func triggerControls() {
        withAnimation { showControls = true }
        // Auto-hide after 4 seconds if playing
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if self.isPlaying {
                withAnimation { self.showControls = false }
            }
        }
    }
    
    private func startProgressTracking() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let repo = self.repository, let channel = self.currentChannel else { return }
            
            let pos = Int64(self.currentTime * 1000)
            let dur = Int64(self.duration * 1000)
            
            // Save progress if valid
            if (pos > 10000 && dur > 0) || channel.type == "live" {
                Task { @MainActor in
                    repo.saveProgress(url: self.currentUrl, pos: pos, dur: dur)
                }
            }
        }
    }
    
    private func reportError(_ title: String, reason: String) {
        DispatchQueue.main.async {
            self.isError = true
            self.errorMessage = "\(title): \(reason)"
            self.isBuffering = false
        }
    }
}
