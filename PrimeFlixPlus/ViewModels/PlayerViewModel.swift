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
    
    // Scrubbing State
    @Published var isScrubbing: Bool = false
    
    // Metadata (Enriched)
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
    private let omdbClient = OmdbClient()
    private var currentChannel: Channel?
    private var cancellables = Set<AnyCancellable>()
    private var controlHideTimer: Timer?
    private var autoPlayTimer: Timer?
    
    // Anti-Rubberband Logic
    private var isSeekingCommit: Bool = false
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
        Task {
            await fetchRichMetadata(channel: channel)
            await checkForNextEpisode()
        }
        
        loadAlternatives()
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
                guard let self = self else { return }
                
                // CRITICAL: Ignore engine time if user is scrubbing OR we just committed a seek
                if self.isScrubbing || self.isSeekingCommit { return }
                
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
        playerEngine.togglePlayPause()
        triggerControls()
    }
    
    func seekForward() {
        let newTime = currentTime + 10
        startScrubbing(translation: 0, screenWidth: 1) // Just to trigger UI state if needed
        currentTime = newTime
        endScrubbing()
    }
    
    func seekBackward() {
        let newTime = currentTime - 10
        startScrubbing(translation: 0, screenWidth: 1)
        currentTime = newTime
        endScrubbing()
    }
    
    /// Starts local UI scrubbing without seeking engine yet
    func startScrubbing(translation: CGFloat, screenWidth: CGFloat) {
        if !isScrubbing {
            isScrubbing = true
        }
        triggerControls(forceShow: true)
        
        if screenWidth > 1 {
            let percent = Double(translation / screenWidth)
            // Dynamic Scrub Speed: Longer videos scrub faster
            let totalDuration = duration > 0 ? duration : 3600
            let sensitivity = max(120.0, totalDuration * 0.15)
            
            let delta = sensitivity * percent
            self.currentTime = max(0, min(currentTime + delta, duration))
        }
    }
    
    /// Commits the seek
    func endScrubbing() {
        isScrubbing = false
        isSeekingCommit = true // Lock incoming time updates
        
        playerEngine.seek(to: currentTime)
        
        // Cooldown: Ignore engine time updates for 1.5 seconds to prevent "Rubber Banding"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isSeekingCommit = false
        }
        
        // Ensure play resumes if it was just a seek action
        if !playerEngine.isPlaying {
            // Optional: Auto-resume on seek? Usually user expects this.
            // playerEngine.play()
        }
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
    
    // MARK: - Smart Metadata Fetcher
    
    private func fetchRichMetadata(channel: Channel) async {
        let info = TitleNormalizer.parse(rawTitle: channel.canonicalTitle ?? channel.title)
        let isSeries = (channel.type == "series" || channel.type == "series_episode")
        
        if let cover = channel.cover, let url = URL(string: cover) { self.posterImage = url }
        if let ov = channel.overview, !ov.isEmpty { self.videoOverview = ov }
        
        guard let match = await tmdbClient.findBestMatch(
            title: info.normalizedTitle,
            year: info.year,
            type: isSeries ? "series" : "movie"
        ) else { return }
        
        if isSeries {
            let seasonNum = Int(channel.season)
            let episodeNum = Int(channel.episode)
            
            if seasonNum > 0 {
                if let seasonData = try? await tmdbClient.getTvSeason(tvId: match.id, seasonNumber: seasonNum) {
                    if let ep = seasonData.episodes.first(where: { $0.episodeNumber == episodeNum }) {
                        await MainActor.run {
                            self.videoTitle = "S\(seasonNum) E\(episodeNum) - \(ep.name)"
                            self.videoOverview = ep.overview ?? self.videoOverview
                            self.videoRating = String(format: "%.1f", ep.voteAverage ?? 0.0)
                            if let still = ep.stillPath {
                                self.posterImage = URL(string: "https://image.tmdb.org/t/p/original\(still)")
                            } else if let poster = match.poster {
                                self.posterImage = URL(string: "https://image.tmdb.org/t/p/w500\(poster)")
                            }
                        }
                        return
                    }
                }
            }
            
            if let details = try? await tmdbClient.getTvDetails(id: match.id) {
                await MainActor.run {
                    self.videoYear = String(details.firstAirDate?.prefix(4) ?? "")
                    if self.videoOverview.isEmpty { self.videoOverview = details.overview ?? "" }
                }
            }
            
        } else {
            if let details = try? await tmdbClient.getMovieDetails(id: match.id) {
                await MainActor.run {
                    self.videoOverview = details.overview ?? self.videoOverview
                    self.videoYear = String(details.releaseDate?.prefix(4) ?? "")
                    self.videoRating = String(format: "%.1f", details.voteAverage ?? 0.0)
                    if let backdrop = details.backdropPath {
                        self.posterImage = URL(string: "https://image.tmdb.org/t/p/original\(backdrop)")
                    }
                }
            }
        }
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
