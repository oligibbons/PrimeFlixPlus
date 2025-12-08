import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class PlayerViewModel: ObservableObject {
    
    // MARK: - Engine
    private let playerEngine = VLCPlayerEngine()
    private var nextEpisodeService: NextEpisodeService?
    
    // MARK: - UI State
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = true
    @Published var isError: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showControls: Bool = false
    
    // Overlays
    @Published var showMiniDetails: Bool = false
    @Published var showTrackSelection: Bool = false
    @Published var showVersionSelection: Bool = false
    @Published var showAutoPlay: Bool = false
    
    // MARK: - Playback Data
    @Published var videoTitle: String = ""
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var currentUrl: String = ""
    @Published var playbackRate: Float = 1.0
    @Published var qualityBadge: String = "HD"
    @Published var isScrubbing: Bool = false
    
    // Metadata
    @Published var videoOverview: String = ""
    @Published var videoYear: String = ""
    @Published var videoRating: String = ""
    @Published var posterImage: URL? = nil
    @Published var isFavorite: Bool = false
    
    // Tracks
    @Published var audioTracks: [String] = []
    @Published var currentAudioIndex: Int = 0
    @Published var subtitleTracks: [String] = []
    @Published var currentSubtitleIndex: Int = 0
    
    // Next Ep
    @Published var nextEpisode: Channel? = nil
    @Published var canPlayNext: Bool = false
    @Published var autoPlayCounter: Int = 20
    
    // Versions
    @Published var alternativeVersions: [Channel] = []
    
    // Internal
    private var repository: PrimeFlixRepository?
    private let tmdbClient = TmdbClient()
    private var currentChannel: Channel?
    private var cancellables = Set<AnyCancellable>()
    private var controlHideTimer: Timer?
    private var autoPlayTimer: Timer?
    private var lastSavedTime: Double = 0
    
    // MARK: - Configuration
    
    func configure(repository: PrimeFlixRepository, channel: Channel) {
        self.repository = repository
        self.currentChannel = channel
        self.videoTitle = channel.title
        self.isFavorite = channel.isFavorite
        self.currentUrl = channel.url
        self.qualityBadge = channel.quality ?? "HD"
        self.nextEpisodeService = NextEpisodeService(context: repository.container.viewContext)
        
        let speed = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
        self.playbackRate = speed > 0 ? Float(speed) : 1.0
        
        setupEngineBindings()
        
        // Start Playback
        playerEngine.setRate(self.playbackRate)
        playerEngine.load(url: channel.url, isLive: channel.type == "live", is4K: channel.quality?.contains("4K") ?? false)
        
        // Metadata & Logic
        fetchExtendedMetadata()
        loadAlternatives()
        Task { await checkForNextEpisode() }
        
        triggerControls(forceShow: true)
    }
    
    func assignView(_ view: UIView) {
        playerEngine.attach(to: view)
    }
    
    private func setupEngineBindings() {
        // Sync Engine State -> ViewModel State
        
        playerEngine.$currentTime
            .receive(on: RunLoop.main)
            .sink { [weak self] time in
                guard let self = self, !self.isScrubbing else { return }
                self.currentTime = time
                
                // Save Progress periodically
                if abs(time - self.lastSavedTime) > 10 {
                    self.saveProgress()
                }
            }
            .store(in: &cancellables)
        
        playerEngine.$duration
            .receive(on: RunLoop.main)
            .assign(to: \.duration, on: self)
            .store(in: &cancellables)
        
        playerEngine.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                self?.isPlaying = playing
                if !playing { self?.triggerControls(forceShow: true) }
            }
            .store(in: &cancellables)
        
        playerEngine.$isBuffering
            .receive(on: RunLoop.main)
            .assign(to: \.isBuffering, on: self)
            .store(in: &cancellables)
        
        playerEngine.$error
            .receive(on: RunLoop.main)
            .sink { [weak self] err in
                if let err = err {
                    self?.isError = true
                    self?.errorMessage = err
                    self?.triggerControls(forceShow: true)
                }
            }
            .store(in: &cancellables)
            
        // Track Sync
        playerEngine.$audioTracks.assign(to: \.audioTracks, on: self).store(in: &cancellables)
        playerEngine.$subtitleTracks.assign(to: \.subtitleTracks, on: self).store(in: &cancellables)
        playerEngine.$currentAudioIndex.assign(to: \.currentAudioIndex, on: self).store(in: &cancellables)
        playerEngine.$currentSubtitleIndex.assign(to: \.currentSubtitleIndex, on: self).store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    func togglePlayPause() {
        if playerEngine.isPlaying {
            playerEngine.pause()
        } else {
            playerEngine.play()
            // Dismiss overlays
            showMiniDetails = false
            showTrackSelection = false
            showVersionSelection = false
        }
        triggerControls()
    }
    
    func seekForward() { playerEngine.seek(to: currentTime + 10); triggerControls() }
    func seekBackward() { playerEngine.seek(to: currentTime - 10); triggerControls() }
    
    func startScrubbing(translation: CGFloat, screenWidth: CGFloat) {
        isScrubbing = true
        triggerControls(forceShow: true)
        let percent = Double(translation / screenWidth)
        let delta = max(120.0, duration * 0.1) * percent
        self.currentTime = max(0, min(currentTime + delta, duration))
    }
    
    func endScrubbing() {
        isScrubbing = false
        playerEngine.seek(to: currentTime)
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        self.playbackRate = speed
        playerEngine.setRate(speed)
    }
    
    func setAudioTrack(index: Int) { playerEngine.setAudioTrack(index) }
    func setSubtitleTrack(index: Int) { playerEngine.setSubtitleTrack(index) }
    
    func switchVersion(_ newChannel: Channel) {
        saveProgress()
        configure(repository: repository!, channel: newChannel)
        showVersionSelection = false
    }
    
    func restartPlayback() {
        playerEngine.seek(to: 0)
        playerEngine.play()
    }
    
    func cleanup() {
        saveProgress()
        playerEngine.cleanup()
        cancellables.removeAll()
        controlHideTimer?.invalidate()
        autoPlayTimer?.invalidate()
    }
    
    // MARK: - Logic Helpers
    
    func triggerControls(forceShow: Bool = false) {
        withAnimation { showControls = true }
        controlHideTimer?.invalidate()
        
        if (isPlaying || !forceShow) && !isError {
            controlHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.isPlaying && !self.isScrubbing && !self.showMiniDetails {
                    withAnimation { self.showControls = false }
                }
            }
        }
    }
    
    func checkForNextEpisode() async {
        guard let current = currentChannel, let service = nextEpisodeService else { return }
        
        // Use the new Service to find the next episode
        if let next = await Task(priority: .userInitiated, operation: {
            return service.findNextEpisode(currentChannel: current)
        }).value {
            await MainActor.run {
                self.nextEpisode = next
                self.canPlayNext = true
            }
        }
    }
    
    private func loadAlternatives() {
        guard let repo = repository, let current = currentChannel else { return }
        let service = VersioningService(context: repo.container.viewContext)
        let versions = service.getVersions(for: current)
        self.alternativeVersions = versions.filter { $0.url != current.url }
    }
    
    private func saveProgress() {
        guard let repo = repository, let channel = currentChannel else { return }
        self.lastSavedTime = currentTime
        let pos = Int64(currentTime * 1000)
        let dur = Int64(duration * 1000)
        
        if (pos > 10000 && dur > 0) || channel.type == "live" {
            repo.saveProgress(url: channel.url, pos: pos, dur: dur)
        }
    }
    
    private func fetchExtendedMetadata() {
        guard let channel = currentChannel else { return }
        if let cover = channel.cover, let url = URL(string: cover) { self.posterImage = url }
        
        let _ = TitleNormalizer.parse(rawTitle: channel.title)
        
        // FIX: Corrected type name (removed "TmdbClient.")
        Task.detached {
            let _: [TmdbTrendingItem] = []
        }
    }
    
    func toggleFavorite() {
        guard let channel = currentChannel else { return }
        repository?.toggleFavorite(channel)
        isFavorite.toggle()
    }
    
    // Auto Play Logic
    func triggerAutoPlay() {
        guard canPlayNext else { return }
        showAutoPlay = true
        autoPlayCounter = 20
        autoPlayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.autoPlayCounter > 0 { self.autoPlayCounter -= 1 }
            else { self.confirmAutoPlay() }
        }
    }
    
    func cancelAutoPlay() {
        autoPlayTimer?.invalidate()
        showAutoPlay = false
    }
    
    func confirmAutoPlay() {
        autoPlayTimer?.invalidate()
        if let next = nextEpisode {
            NotificationCenter.default.post(name: NSNotification.Name("PlayNextEpisode"), object: next)
        }
    }
}
