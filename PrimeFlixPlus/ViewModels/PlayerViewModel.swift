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
        self.currentUrl = channel.url
        setupPlayer(url: channel.url)
    }
    
    func cleanup() {
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        progressTimer?.invalidate()
        player?.pause()
        player = nil
    }
    
    private func setupPlayer(url: String) {
        guard let streamUrl = URL(string: url) else { return }
        let item = AVPlayerItem(url: streamUrl)
        self.player = AVPlayer(playerItem: item)
        self.player?.play()
        self.isPlaying = true
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
            if let d = self?.player?.currentItem?.duration.seconds, d.isFinite { self?.duration = d }
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
