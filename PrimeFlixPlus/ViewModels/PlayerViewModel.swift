import Foundation
import AVKit
import AVFoundation // CRITICAL: Required for AVURLAsset
import Combine
import SwiftUI

class PlayerViewModel: ObservableObject {
    
    @Published var player: AVPlayer?
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var isError: Bool = false
    @Published var errorMessage: String? = nil
    @Published var videoTitle: String = ""
    @Published var currentUrl: String = ""
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var showControls: Bool = false
    
    private var repository: PrimeFlixRepository?
    private var timeObserver: Any?
    private var itemObservers: Set<AnyCancellable> = []
    private var progressTimer: Timer?
    
    func configure(repository: PrimeFlixRepository, channel: Channel) {
        self.repository = repository
        self.videoTitle = channel.title
        
        // 1. NUCLEAR URL SANITIZATION
        var rawUrl = channel.url
        
        // Fix the specific scheme spacing issue if present
        if rawUrl.contains(": //") {
            rawUrl = rawUrl.replacingOccurrences(of: ": //", with: "://")
        }
        // Fix spaces encoded incorrectly by previous attempts
        if rawUrl.contains(":%20//") {
            rawUrl = rawUrl.replacingOccurrences(of: ":%20//", with: "://")
        }
        
        // Finally, fix any other spaces in the path (standard encoding)
        let cleanUrl = rawUrl.replacingOccurrences(of: " ", with: "%20")
        
        self.currentUrl = cleanUrl
        print("▶️ Attempting playback: \(cleanUrl)")
        
        setupPlayer(url: cleanUrl)
    }
    
    func cleanup() {
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        progressTimer?.invalidate()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
    
    private func setupPlayer(url: String) {
        guard let streamUrl = URL(string: url) else {
            self.isError = true
            self.errorMessage = "Invalid URL Format"
            print("❌ Invalid URL String: \(url)")
            return
        }
        
        // 2. HEADERS (User-Agent)
        // Switching to VLC/3.0.16 which is the 'Gold Standard' for IPTV compatibility
        let headers: [String: Any] = [
            "User-Agent": "VLC/3.0.16 LibVLC/3.0.16"
        ]
        
        // 3. ASSET CREATION
        // Use string literal to ensure compatibility
        let asset = AVURLAsset(url: streamUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        
        // 4. MONITORING
        let statusObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .failed:
                    self?.isError = true
                    
                    // FIXED: Correctly cast Error to NSError to access localizedFailureReason
                    let error = item.error as NSError?
                    let errDescription = error?.localizedDescription ?? "Unknown Stream Error"
                    let reason = error?.localizedFailureReason ?? ""
                    
                    self?.errorMessage = "\(errDescription) \(reason)"
                    print("❌ Player Failed: \(errDescription) | Reason: \(reason) | URL: \(url)")
                    
                case .readyToPlay:
                    self?.isError = false
                    self?.duration = item.duration.seconds
                    print("✅ Ready to play. Duration: \(item.duration.seconds)")
                    self?.player?.play()
                    self?.isPlaying = true
                    
                default:
                    break
                }
            }
        
        itemObservers.insert(AnyCancellable(statusObserver))
        
        // 5. INITIALIZE PLAYER
        self.player = AVPlayer(playerItem: item)
        self.player?.actionAtItemEnd = .pause
        
        // Periodic Time Observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
        
        startProgressTracking()
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
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self, let repo = self.repository else { return }
            let pos = Int64(self.currentTime * 1000)
            let dur = Int64(self.duration * 1000)
            if pos > 5000 {
                 Task { await MainActor.run { repo.saveProgress(url: self.currentUrl, pos: pos, dur: dur) } }
            }
        }
    }
}
