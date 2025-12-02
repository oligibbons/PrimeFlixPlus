import Foundation
import AVKit
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
        
        // 1. Sanitize URL (Fix spaces)
        let cleanUrl = channel.url.replacingOccurrences(of: " ", with: "%20")
        self.currentUrl = cleanUrl
        
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
            self.errorMessage = "Invalid URL"
            return
        }
        
        // 2. CRITICAL FIX: Create Asset with Custom Headers
        // Many IPTV providers block default AVPlayer User-Agent. We impersonate VLC/Browser.
        let headers: [String: Any] = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"
        ]
        
        let asset = AVURLAsset(url: streamUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        
        // 3. Monitor Playback Status
        let statusObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .failed:
                    self?.isError = true
                    self?.errorMessage = item.error?.localizedDescription ?? "Stream Error"
                    print("❌ Player Error: \(String(describing: item.error))")
                case .readyToPlay:
                    self?.isError = false
                    self?.duration = item.duration.seconds
                    print("✅ Ready to play")
                    self?.player?.play() // Auto-play when ready
                    self?.isPlaying = true
                default: break
                }
            }
        
        itemObservers.insert(AnyCancellable(statusObserver))
        
        self.player = AVPlayer(playerItem: item)
        
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
