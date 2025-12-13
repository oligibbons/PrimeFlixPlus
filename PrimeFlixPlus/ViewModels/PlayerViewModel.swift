import Foundation
import Combine
import SwiftUI
import CoreData
import UIKit // For lifecycle notifications

@MainActor
class PlayerViewModel: ObservableObject {
    
    // MARK: - Engine
    private let playerEngine = VLCPlayerEngine()
    
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
    
    // NEW: End of Playback Prompt
    @Published var showFavoritesPrompt: Bool = false
    
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
    private var hasTriggeredAutoPlay: Bool = false
    
    // Versions
    @Published var alternativeVersions: [Channel] = []
    
    // Internal
    private var repository: PrimeFlixRepository?
    private let tmdbClient = TmdbClient()
    
    private var epgService: EpgService?
    private var currentChannel: Channel?
    private var cancellables = Set<AnyCancellable>()
    private var controlHideTimer: Timer?
    private var autoPlayTimer: Timer?
    
    private var isSeekingCommit: Bool = false
    private var lastSavedTime: Double = 0
    private var hasShownFavPrompt: Bool = false
    
    // MARK: - Configuration
    
    func configure(repository: PrimeFlixRepository, channel: Channel) {
        self.repository = repository
        self.currentChannel = channel
        self.videoTitle = channel.title
        self.isFavorite = channel.isFavorite
        self.currentUrl = channel.url
        self.qualityBadge = channel.quality ?? "HD"
        self.epgService = EpgService(context: repository.container.viewContext)
        
        // Reset State
        self.hasTriggeredAutoPlay = false
        self.showAutoPlay = false
        self.showFavoritesPrompt = false
        self.hasShownFavPrompt = false
        self.autoPlayCounter = 20
        self.isBuffering = true
        
        // 1. Read Settings
        let speed = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
        self.playbackRate = speed > 0 ? Float(speed) : 1.0
        
        setupEngineBindings()
        setupLifecycleObservers()
        
        // 2. Resume Logic
        checkForResume(channel: channel)
        
        // 3. Metadata
        Task {
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
    
    // MARK: - Lifecycle Management (Fix for "Stuck" player)
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppResume()
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleAppResume() {
        // If we were playing before, or if the view is active, ensure engine is alive
        if self.currentTime > 0 && !self.isError {
            // Re-assert playback state if needed
            if self.isPlaying {
                playerEngine.play()
            }
        }
    }
    
    // MARK: - Resume Logic
    
    private func checkForResume(channel: Channel) {
        guard let repo = repository else { return }
        
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
            
            // Logic: Resume if > 1 minute watched and < 95% complete
            if savedDur > 60 && savedPos > 60 && savedPos < (savedDur * 0.95) {
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
        
        // 1. Load Engine
        playerEngine.setRate(self.playbackRate)
        
        playerEngine.load(
            url: channel.url,
            isLive: channel.type == "live",
            quality: channel.quality,
            startTime: time
        )
        
        // 2. Apply Defaults
        let defDeinterlace = UserDefaults.standard.bool(forKey: "defaultDeinterlace")
        let defRatio = UserDefaults.standard.string(forKey: "defaultAspectRatio") ?? "Default"
        
        if defDeinterlace {
            self.isDeinterlaceEnabled = true
        } else {
            self.isDeinterlaceEnabled = (channel.type == "live")
        }
        
        self.aspectRatio = defRatio
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
            
            // Auto-save every 10s
            if abs(time - self.lastSavedTime) > 10 {
                self.saveProgress()
            }
            
            // 1. Auto-Play Trigger (Next Episode)
            if self.duration > 0 && !self.hasTriggeredAutoPlay && self.canPlayNext {
                let remaining = self.duration - time
                // Trigger 20s before end
                if remaining <= 20 && remaining > 5 {
                    self.triggerAutoPlay()
                }
            }
            
            // 2. Favorites Prompt Trigger (Finished)
            if self.duration > 0 && !self.hasShownFavPrompt && !self.isFavorite {
                let progress = time / self.duration
                if progress > 0.95 {
                    // Only show if we are NOT auto-playing next ep
                    if !self.showAutoPlay {
                        self.hasShownFavPrompt = true
                        self.showFavoritesPrompt = true
                    }
                }
            }
            
        }.store(in: &cancellables)
        
        playerEngine.$duration.receive(on: RunLoop.main).assign(to: \.duration, on: self).store(in: &cancellables)
        
        // Updated: Handle "Stuck Pause Icon" by strictly syncing UI state
        playerEngine.$isPlaying.receive(on: RunLoop.main).sink { [weak self] playing in
            self?.isPlaying = playing
            if !playing {
                self?.triggerControls(forceShow: true)
            }
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
    
    // MARK: - Actions (Scrubbing Fix)
    
    func togglePlayPause() { playerEngine.togglePlayPause(); triggerControls() }
    
    func seekForward() {
        let newTime = currentTime + 10
        startScrubbing(translation: 0, screenWidth: 1) // Dummy scrub
        self.currentTime = max(0, min(newTime, duration))
        endScrubbing()
    }
    
    func seekBackward() {
        let newTime = currentTime - 10
        self.currentTime = max(0, min(newTime, duration))
        endScrubbing()
    }
    
    func startScrubbing(translation: CGFloat, screenWidth: CGFloat) {
        if !isScrubbing { isScrubbing = true }
        triggerControls(forceShow: true)
        
        if screenWidth > 1 {
            let percent = Double(translation / screenWidth)
            let totalDuration = duration > 0 ? duration : 3600
            
            // --- SENSITIVITY FIX (Drastically Reduced) ---
            // Old Default: 0.2 (way too fast). New Default: 0.05
            let userSensitivity = UserDefaults.standard.double(forKey: "scrubSensitivity")
            let sensitivityFactor = userSensitivity > 0 ? userSensitivity : 0.05
            
            let delta = (totalDuration * sensitivityFactor) * percent
            
            self.currentTime = max(0, min(currentTime + delta, duration))
        }
    }
    
    func endScrubbing() {
        isScrubbing = false
        isSeekingCommit = true
        playerEngine.seek(to: currentTime)
        
        // Debounce to prevent UI jumping
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isSeekingCommit = false
        }
        
        if !playerEngine.isPlaying { playerEngine.play() }
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        self.playbackRate = speed
        playerEngine.setRate(speed)
    }
    
    func setAudioTrack(index: Int) { playerEngine.setAudioTrack(index: index) }
    func setSubtitleTrack(index: Int) { playerEngine.setSubtitleTrack(index: index) }
    func refreshTracks() { playerEngine.refreshTracks() }
    
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
    
    func switchVersion(_ newChannel: Channel) {
        saveProgress()
        configure(repository: repository!, channel: newChannel)
        showVersionSelection = false
        // Auto-start the new version
        startPlayback(from: self.currentTime)
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
    
    // MARK: - Auto Play & Favorites Logic
    
    func toggleFavorite() {
        guard let channel = currentChannel else { return }
        repository?.toggleFavorite(channel)
        isFavorite.toggle()
        showFavoritesPrompt = false // Close prompt if opened
    }
    
    func triggerAutoPlay() {
        guard canPlayNext, !hasTriggeredAutoPlay else { return }
        self.hasTriggeredAutoPlay = true
        self.showAutoPlay = true
        self.autoPlayCounter = 20
        
        // FIX: Ensure Timer runs on RunLoop.main
        autoPlayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.autoPlayCounter > 0 {
                    self.autoPlayCounter -= 1
                } else {
                    self.confirmAutoPlay()
                }
            }
        }
    }
    
    func cancelAutoPlay() {
        autoPlayTimer?.invalidate()
        showAutoPlay = false
        hasTriggeredAutoPlay = true // Prevent re-firing
    }
    
    func confirmAutoPlay() {
        autoPlayTimer?.invalidate()
        showAutoPlay = false
        
        if let next = nextEpisode {
            // Post notification for PlayerView to handle the transition (view rebuild)
            NotificationCenter.default.post(name: NSNotification.Name("PlayNextEpisode"), object: next)
        }
    }
    
    // MARK: - Metadata & Internals
    
    private func fetchLiveMetadata(channel: Channel) async {
        guard let service = epgService else { return }
        if let cover = channel.cover, let url = URL(string: cover) { self.posterImage = url }
        await service.refreshEpg(for: [channel])
        let map = service.getCurrentPrograms(for: [channel])
        if let program = map[channel.url] {
            await MainActor.run {
                self.videoTitle = program.title
                self.videoOverview = program.desc ?? "No description available."
                let f = DateFormatter()
                f.timeStyle = .short
                self.videoYear = "\(f.string(from: program.start)) - \(f.string(from: program.end))"
            }
        }
    }
    
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
    
    func triggerControls(forceShow: Bool = false) {
        withAnimation { showControls = true }
        controlHideTimer?.invalidate()
        if (isPlaying || !forceShow) && !isError {
            controlHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.isPlaying && !self.isScrubbing && !self.showMiniDetails {
                        withAnimation { self.showControls = false }
                    }
                }
            }
        }
    }
    
    func checkForNextEpisode() async {
        guard let current = currentChannel, let repo = repository else { return }
        let objectID = current.objectID
        let container = repo.container
        
        Task.detached(priority: .userInitiated) {
            let bgContext = container.newBackgroundContext()
            let service = NextEpisodeService(context: bgContext)
            
            guard let bgChannel = try? bgContext.existingObject(with: objectID) as? Channel else { return }
            if let nextBg = service.findNextEpisode(currentChannel: bgChannel) {
                let nextID = nextBg.objectID
                await MainActor.run {
                    if let mainNext = try? container.viewContext.existingObject(with: nextID) as? Channel {
                        self.nextEpisode = mainNext
                        self.canPlayNext = true
                    }
                }
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
        repo.saveProgress(url: channel.url, pos: pos, dur: dur)
    }
}
