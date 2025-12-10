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
    @Published var showResumePrompt: Bool = false
    @Published var showVideoSettings: Bool = false
    
    // MARK: - Playback Data
    @Published var videoTitle: String = ""
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var currentUrl: String = ""
    @Published var playbackRate: Float = 1.0
    @Published var qualityBadge: String = "HD"
    @Published var isScrubbing: Bool = false
    @Published var resumeTime: Double = 0.0
    
    // Sync State
    @Published var audioDelay: Int = 0
    @Published var subtitleDelay: Int = 0
    
    // Video Settings State
    @Published var isDeinterlaceEnabled: Bool = false
    @Published var aspectRatio: String = "Default"
    
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
    private let omdbClient = OmdbClient()
    
    // NEW: EPG Service for Live TV Metadata
    private var epgService: EpgService?
    
    private var currentChannel: Channel?
    private var cancellables = Set<AnyCancellable>()
    private var controlHideTimer: Timer?
    private var autoPlayTimer: Timer?
    
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
        self.epgService = EpgService(context: repository.container.viewContext) // Init EPG
        
        // 1. Read Global Playback Speed Default
        let speed = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
        self.playbackRate = speed > 0 ? Float(speed) : 1.0
        
        setupEngineBindings()
        
        // 2. Check for Resume Point
        checkForResume(channel: channel)
        
        // 3. Metadata & Logic
        Task {
            // Branch logic based on content type
            if channel.type == "live" {
                await fetchLiveMetadata(channel: channel)
            } else {
                await fetchRichMetadata(channel: channel)
                await checkForNextEpisode()
            }
        }
        
        loadAlternatives()
    }
    
    func assignView(_ view: UIView) {
        playerEngine.attach(to: view)
    }
    
    // MARK: - Resume & Defaults Logic
    
    private func checkForResume(channel: Channel) {
        guard let repo = repository else { return }
        
        // Live TV generally shouldn't resume from a timestamp unless it's catchup (not supported yet)
        if channel.type == "live" {
            startPlayback(from: 0)
            return
        }
        
        let context = repo.container.viewContext
        let req = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
        req.predicate = NSPredicate(format: "channelUrl == %@", channel.url)
        req.fetchLimit = 1
        
        if let progress = try? context.fetch(req).first {
            let savedPos = Double(progress.position) / 1000.0
            let savedDur = Double(progress.duration) / 1000.0
            
            // Resume if > 1 min duration and between 3%-95%
            if savedDur > 60 && savedPos > (savedDur * 0.03) && savedPos < (savedDur * 0.95) {
                self.resumeTime = savedPos
                self.showResumePrompt = true
            } else {
                startPlayback(from: 0)
            }
        } else {
            startPlayback(from: 0)
        }
    }
    
    func startPlayback(from time: Double) {
        guard let channel = currentChannel else { return }
        self.showResumePrompt = false
        
        // 1. Load Engine with Optimization Data
        playerEngine.setRate(self.playbackRate)
        
        playerEngine.load(
            url: channel.url,
            isLive: channel.type == "live",
            quality: channel.quality,
            startTime: time
        )
        
        // 2. Apply User Defaults for Video Settings
        let defDeinterlace = UserDefaults.standard.bool(forKey: "defaultDeinterlace")
        let defRatio = UserDefaults.standard.string(forKey: "defaultAspectRatio") ?? "Default"
        
        // Deinterlace Logic
        if defDeinterlace {
            self.isDeinterlaceEnabled = true
        } else {
            self.isDeinterlaceEnabled = (channel.type == "live")
        }
        
        // Aspect Ratio Logic
        self.aspectRatio = defRatio
        
        // Reset Sync
        self.audioDelay = 0
        self.subtitleDelay = 0
        
        // 3. Push to Engine
        playerEngine.setDeinterlace(self.isDeinterlaceEnabled)
        playerEngine.setAspectRatio(self.aspectRatio)
        
        triggerControls(forceShow: true)
    }
    
    // MARK: - Engine Bindings
    
    private func setupEngineBindings() {
        playerEngine.$currentTime.receive(on: RunLoop.main).sink { [weak self] time in
            guard let self = self else { return }
            if self.isScrubbing || self.isSeekingCommit { return }
            self.currentTime = time
            
            // Auto-save progress
            if abs(time - self.lastSavedTime) > 10 {
                self.saveProgress()
            }
        }.store(in: &cancellables)
        
        playerEngine.$duration.receive(on: RunLoop.main).assign(to: \.duration, on: self).store(in: &cancellables)
        
        playerEngine.$isPlaying.receive(on: RunLoop.main).sink { [weak self] playing in
            self?.isPlaying = playing
            if !playing { self?.triggerControls(forceShow: true) }
        }.store(in: &cancellables)
        
        playerEngine.$isBuffering.receive(on: RunLoop.main).assign(to: \.isBuffering, on: self).store(in: &cancellables)
        
        playerEngine.$error.receive(on: RunLoop.main).sink { [weak self] err in
            if let err = err {
                self?.isError = true
                self?.errorMessage = err
                self?.triggerControls(forceShow: true)
            }
        }.store(in: &cancellables)
            
        // Tracks & Sync
        playerEngine.$audioTracks.assign(to: \.audioTracks, on: self).store(in: &cancellables)
        playerEngine.$subtitleTracks.assign(to: \.subtitleTracks, on: self).store(in: &cancellables)
        playerEngine.$currentAudioIndex.assign(to: \.currentAudioIndex, on: self).store(in: &cancellables)
        playerEngine.$currentSubtitleIndex.assign(to: \.currentSubtitleIndex, on: self).store(in: &cancellables)
        
        playerEngine.$audioDelay.assign(to: \.audioDelay, on: self).store(in: &cancellables)
        playerEngine.$subtitleDelay.assign(to: \.subtitleDelay, on: self).store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    func togglePlayPause() { playerEngine.togglePlayPause(); triggerControls() }
    
    func seekForward() {
        let newTime = currentTime + 10
        startScrubbing(translation: 0, screenWidth: 1)
        currentTime = newTime
        endScrubbing()
    }
    
    func seekBackward() {
        let newTime = currentTime - 10
        startScrubbing(translation: 0, screenWidth: 1)
        currentTime = newTime
        endScrubbing()
    }
    
    func startScrubbing(translation: CGFloat, screenWidth: CGFloat) {
        if !isScrubbing { isScrubbing = true }
        triggerControls(forceShow: true)
        
        if screenWidth > 1 {
            let percent = Double(translation / screenWidth)
            let totalDuration = duration > 0 ? duration : 3600
            let sensitivity = max(120.0, totalDuration * 0.15)
            let delta = sensitivity * percent
            self.currentTime = max(0, min(currentTime + delta, duration))
        }
    }
    
    func endScrubbing() {
        isScrubbing = false
        isSeekingCommit = true
        playerEngine.seek(to: currentTime)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.isSeekingCommit = false }
        if !playerEngine.isPlaying { playerEngine.play() }
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        self.playbackRate = speed
        playerEngine.setRate(speed)
    }
    
    func setAudioTrack(index: Int) { playerEngine.setAudioTrack(index) }
    func setSubtitleTrack(index: Int) { playerEngine.setSubtitleTrack(index) }
    
    // MARK: - Sync & Video Actions
    
    func setAudioDelay(_ ms: Int) { playerEngine.setAudioDelay(ms) }
    func setSubtitleDelay(_ ms: Int) { playerEngine.setSubtitleDelay(ms) }
    
    func toggleDeinterlace() {
        isDeinterlaceEnabled.toggle()
        playerEngine.setDeinterlace(isDeinterlaceEnabled)
    }
    
    func setDeinterlace(_ enabled: Bool) {
        self.isDeinterlaceEnabled = enabled
        playerEngine.setDeinterlace(enabled)
    }
    
    func setAspectRatio(_ ratio: String) {
        self.aspectRatio = ratio
        playerEngine.setAspectRatio(ratio)
    }
    
    // MARK: - Navigation
    
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
    
    // MARK: - Metadata (Live EPG)
    
    private func fetchLiveMetadata(channel: Channel) async {
        guard let service = epgService else { return }
        
        // 1. Setup Basic Info
        if let cover = channel.cover, let url = URL(string: cover) { self.posterImage = url }
        
        // 2. Fetch Fresh EPG
        // We do this in a task to not block basic UI
        await service.refreshEpg(for: [channel])
        
        let map = service.getCurrentPrograms(for: [channel])
        if let program = map[channel.url] {
            await MainActor.run {
                self.videoTitle = program.title
                self.videoOverview = program.desc ?? "No description available."
                
                let f = DateFormatter()
                f.timeStyle = .short
                let timeStr = "\(f.string(from: program.start)) - \(f.string(from: program.end))"
                self.videoYear = timeStr // Re-using videoYear slot for Time display in Player
            }
        } else {
            await MainActor.run {
                self.videoTitle = channel.title
                self.videoOverview = "No program information available."
            }
        }
    }
    
    // MARK: - Metadata (VOD TMDB)
    
    private func fetchRichMetadata(channel: Channel) async {
        let info = TitleNormalizer.parse(rawTitle: channel.canonicalTitle ?? channel.title)
        let isSeries = (channel.type == "series" || channel.type == "series_episode")
        
        if let cover = channel.cover, let url = URL(string: cover) { self.posterImage = url }
        if let ov = channel.overview, !ov.isEmpty { self.videoOverview = ov }
        
        guard let match = await tmdbClient.findBestMatch(title: info.normalizedTitle, year: info.year, type: isSeries ? "series" : "movie") else { return }
        
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
        
        // For Live TV, we might simply mark it as "watched" recently without saving a specific time
        // but keeping it in the repo updates "Recently Watched" logic.
        repo.saveProgress(url: channel.url, pos: pos, dur: dur)
    }
    
    func toggleFavorite() {
        guard let channel = currentChannel else { return }
        repository?.toggleFavorite(channel)
        isFavorite.toggle()
    }
    
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
    
    func cancelAutoPlay() { autoPlayTimer?.invalidate(); showAutoPlay = false }
    
    func confirmAutoPlay() {
        autoPlayTimer?.invalidate()
        if let next = nextEpisode {
            NotificationCenter.default.post(name: NSNotification.Name("PlayNextEpisode"), object: next)
        }
    }
}
