import Foundation
import AVKit
import AVFoundation
import Combine
import SwiftUI

class PlayerViewModel: NSObject, ObservableObject, AVAssetResourceLoaderDelegate {
    
    // UI State
    @Published var player: AVPlayer?
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var isError: Bool = false
    @Published var errorMessage: String? = nil
    
    // Metadata
    @Published var videoTitle: String = ""
    @Published var currentUrl: String = "" // Displayed in Debug UI
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var showControls: Bool = false
    
    // Dependencies
    private var repository: PrimeFlixRepository?
    private var timeObserver: Any?
    private var itemObservers: Set<AnyCancellable> = []
    private var progressTimer: Timer?
    
    // MARK: - Configuration
    
    func configure(repository: PrimeFlixRepository, channel: Channel) {
        self.repository = repository
        self.videoTitle = channel.title
        
        // 1. Activate Audio Session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Audio Session Error: \(error)")
        }
        
        // 2. ROBUST URL SANITIZATION
        guard let sanitizedUrl = sanitize(url: channel.url) else {
            reportError("Invalid URL", reason: "Could not parse: \(channel.url)")
            return
        }
        
        self.currentUrl = sanitizedUrl
        print("▶️ Attempting playback: \(sanitizedUrl)")
        
        setupPlayer(url: sanitizedUrl)
    }
    
    private func sanitize(url: String) -> String? {
        // Handle Basic Cleanups
        var raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Fix double-slash prefix issue if present
        if raw.hasPrefix("http:/") && !raw.hasPrefix("http://") {
            raw = raw.replacingOccurrences(of: "http:/", with: "http://")
        }
        
        // Attempt to parse components
        // Note: URLComponents(string:) fails if there are unencoded spaces
        // So we pre-encode spaces first
        let encodedSpaces = raw.replacingOccurrences(of: " ", with: "%20")
        
        guard var components = URLComponents(string: encodedSpaces) else {
            // Fallback: If it's a total mess, return raw and pray
            return raw
        }
        
        // Ensure Scheme
        if components.scheme == nil { components.scheme = "http" }
        
        // MKV -> MP4 Swap (Apple TV Compatibility)
        // Only applies if the URL is explicitly .mkv
        // We DO NOT touch .m3u8
        if components.path.hasSuffix(".mkv") {
            print("🔧 Detected MKV. Swapping to MP4...")
            let newPath = String(components.path.dropLast(4)) + ".mp4"
            components.path = newPath
        }
        
        return components.string
    }
    
    // MARK: - Player Setup
    
    private func setupPlayer(url: String) {
        guard let streamUrl = URL(string: url) else {
            reportError("Malformed URL", reason: url)
            return
        }
        
        // 3. ASSET CREATION
        // Headers to mimic VLC (helps with some strict firewalls)
        let headers: [String: Any] = [
            "User-Agent": "VLC/3.0.16 LibVLC/3.0.16"
        ]
        
        let asset = AVURLAsset(url: streamUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        
        // 4. SSL BYPASS
        asset.resourceLoader.setDelegate(self, queue: DispatchQueue.main)
        
        let item = AVPlayerItem(asset: asset)
        
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
        
        // 6. INITIALIZE
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
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
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForResponseTo authenticationChallenge: URLAuthenticationChallenge) -> Bool {
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
                let reason = error.localizedFailureReason ?? ""
                let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
                let underlyingReason = underlying?.localizedDescription ?? ""
                
                print("❌ Player Failed: \(desc) | \(reason) | \(underlyingReason)")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if self.isPlaying {
                withAnimation { self.showControls = false }
            }
        }
    }
    
    private func startProgressTracking() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let repo = self.repository else { return }
            let pos = Int64(self.currentTime * 1000)
            let dur = Int64(self.duration * 1000)
            if pos > 10000 && dur > 0 {
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
