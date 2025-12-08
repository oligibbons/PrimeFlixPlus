import SwiftUI
import TVVLCKit

struct PlayerView: View {
    let channel: Channel
    let onBack: () -> Void
    
    // Callback to switch media (e.g. Next Episode) without closing the player view entirely
    var onPlayChannel: ((Channel) -> Void)? = nil
    
    @StateObject private var viewModel = PlayerViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // MARK: - Focus State Logic
    enum PlayerFocus: Hashable {
        case videoSurface // The "Playhead" / Scrubbing Zone
        case upperControls // The Heart Button / Top Bar
        case miniDetails // The Swipe-Down overlay
        case autoPlayOverlay // The Timer Overlay
        case trackSelection // Focus for Audio/Subtitle selection
        case versionSelection // NEW: Focus for Version selection
    }
    @FocusState private var focusedField: PlayerFocus?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geo in
                ZStack {
                    // 1. VLC Video Surface (The "Playhead")
                    // Acts as the base layer.
                    VLCVideoSurface(viewModel: viewModel)
                        .ignoresSafeArea()
                    
                    // 2. Interaction Layer (Inputs)
                    // This sits on top of the video to capture all focus and gestures.
                    // CRITICAL FIX: Disable focus when ANY overlay is active
                    Color.clear
                        .contentShape(Rectangle())
                        .focusable(!viewModel.showMiniDetails && !viewModel.showAutoPlay && !viewModel.showTrackSelection && !viewModel.showVersionSelection)
                        .focused($focusedField, equals: .videoSurface)
                        
                        // --- GESTURES ---
                        // Handles both Horizontal (Scrub) and Vertical (Overlay) swipes
                        .background(
                            SiriRemoteSwipeHandler(
                                onPan: { x, y in
                                    // LOCK: Disable scrubbing if Overlays are open
                                    if viewModel.showMiniDetails || viewModel.showAutoPlay || viewModel.showTrackSelection || viewModel.showVersionSelection { return }
                                    
                                    // Priority: Scrubbing (Horizontal)
                                    if abs(x) > abs(y) {
                                        viewModel.startScrubbing(translation: x, screenWidth: geo.size.width)
                                    }
                                    // Priority: Overlay (Vertical Down)
                                    // Threshold > 50 ensures distinct intent
                                    else if y > 50 {
                                        withAnimation {
                                            viewModel.showMiniDetails = true
                                            focusedField = .miniDetails
                                        }
                                    }
                                },
                                onEnd: {
                                    if !viewModel.showMiniDetails && !viewModel.showAutoPlay && !viewModel.showTrackSelection && !viewModel.showVersionSelection {
                                        viewModel.endScrubbing()
                                    }
                                }
                            )
                        )
                    
                        // Discrete Moves (D-Pad / Arrows)
                        .onMoveCommand { direction in
                            // LOCK: Do not allow player navigation if overlay is open
                            if viewModel.showMiniDetails || viewModel.showAutoPlay || viewModel.showTrackSelection || viewModel.showVersionSelection { return }
                            
                            viewModel.triggerControls(forceShow: true)
                            
                            switch direction {
                            case .left:
                                viewModel.seekBackward()
                            case .right:
                                viewModel.seekForward()
                            case .up:
                                // Navigate "Up" to the Controls layer
                                if viewModel.showControls {
                                    focusedField = .upperControls
                                } else {
                                    viewModel.triggerControls(forceShow: true)
                                }
                            case .down:
                                // Navigate "Down" to Mini Details
                                withAnimation {
                                    viewModel.showMiniDetails = true
                                    focusedField = .miniDetails
                                }
                            @unknown default:
                                break
                            }
                        }
                        
                        .onPlayPauseCommand {
                            // LOCK: Disable toggle if overlay is active
                            if !viewModel.showMiniDetails && !viewModel.showAutoPlay && !viewModel.showTrackSelection && !viewModel.showVersionSelection {
                                viewModel.togglePlayPause()
                            }
                        }
                        .onExitCommand {
                            // Standard Back behavior when on the playhead
                            print("🔙 Menu Pressed on Playhead - Exiting")
                            viewModel.cleanup()
                            onBack()
                        }
                }
            }
            
            // 3. Buffering State
            if viewModel.isBuffering {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 20) {
                        ProgressView()
                            .tint(CinemeltTheme.accent)
                            .scaleEffect(2.5)
                        Text("Loading Stream...")
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(CinemeltTheme.cream)
                    }
                }
            }
            
            // 4. Scrubbing Preview (Live Thumbnail style)
            if viewModel.isScrubbing {
                VStack {
                    Spacer()
                    ZStack {
                        // Background Plate
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .frame(width: 280, height: 180)
                            .shadow(radius: 20)
                        
                        // Fallback Image (Backdrop)
                        AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.black
                        }
                        .frame(width: 280, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .opacity(0.6)
                        
                        // Timecode (Hero)
                        Text(formatTime(viewModel.currentTime))
                            .font(CinemeltTheme.fontTitle(40))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 5)
                    }
                    .padding(.bottom, 120) // Push above the progress bar
                    .transition(.opacity)
                }
            }
            
            // 5. Error State
            if viewModel.isError {
                errorOverlay
            }
            
            // 6. Mini Details Overlay (Swipe Down)
            if viewModel.showMiniDetails {
                MiniDetailsOverlay(
                    viewModel: viewModel,
                    channel: channel,
                    onPlayNext: {
                        if let next = viewModel.nextEpisode {
                            viewModel.cleanup()
                            onPlayChannel?(next)
                        }
                    },
                    onClose: {
                        withAnimation {
                            viewModel.showMiniDetails = false
                        }
                        // Delay focus return slightly to allow view to disappear
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focusedField = .videoSurface
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(50)
                .focusSection() // Ensures focus is trapped here
                .focused($focusedField, equals: .miniDetails)
            }
            
            // 7. Track Selection Overlay
            if viewModel.showTrackSelection {
                TrackSelectionOverlay(
                    viewModel: viewModel,
                    onClose: {
                        withAnimation { viewModel.showTrackSelection = false }
                        focusedField = .videoSurface
                    }
                )
                .zIndex(55)
                .focusSection()
                .onAppear {
                    // Trap focus
                    focusedField = .trackSelection
                }
                .focused($focusedField, equals: .trackSelection)
            }
            
            // 8. Version Selection Overlay (NEW)
            if viewModel.showVersionSelection {
                VersionSelectionOverlay(
                    viewModel: viewModel,
                    onClose: {
                        withAnimation { viewModel.showVersionSelection = false }
                        focusedField = .videoSurface
                    }
                )
                .zIndex(56)
                .focusSection()
                .onAppear {
                    focusedField = .versionSelection
                }
                .focused($focusedField, equals: .versionSelection)
            }
            
            // 9. Auto Play Overlay (Timer)
            if viewModel.showAutoPlay {
                AutoPlayOverlay(viewModel: viewModel)
                    .zIndex(60)
                    .focusSection()
                    .onAppear {
                        // Trap focus immediately
                        focusedField = .autoPlayOverlay
                    }
                    .focused($focusedField, equals: .autoPlayOverlay)
            }
            
            // 10. Controls Overlay
            // We pass the focus binding down so the overlay knows if it's active
            if viewModel.showControls && !viewModel.showMiniDetails && !viewModel.showAutoPlay && !viewModel.showTrackSelection && !viewModel.showVersionSelection {
                ControlsOverlayView(
                    viewModel: viewModel,
                    channel: channel,
                    focusedField: $focusedField,
                    onShowTracks: {
                        withAnimation { viewModel.showTrackSelection = true }
                        focusedField = .trackSelection
                    },
                    onShowVersions: { // NEW Callback
                        withAnimation { viewModel.showVersionSelection = true }
                        focusedField = .versionSelection
                    }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        // Force focus to playhead on load
        .onAppear {
            viewModel.configure(repository: repository, channel: channel)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .videoSurface
            }
        }
        // Listener for Auto-Play Trigger
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PlayNextEpisode"))) { note in
            if let nextChannel = note.object as? Channel {
                viewModel.cleanup()
                onPlayChannel?(nextChannel)
            }
        }
        // Auto-Focus logic for Play/Pause state
        .onChange(of: viewModel.showControls) { show in
            if show && !viewModel.showMiniDetails && !viewModel.showAutoPlay && !viewModel.showTrackSelection && !viewModel.showVersionSelection {
                focusedField = .videoSurface
            }
        }
        .onChange(of: focusedField) { focus in
            if focus == .upperControls {
                viewModel.triggerControls(forceShow: true)
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
    
    // MARK: - Error Overlay
    private var errorOverlay: some View {
        ZStack {
            Color.black.opacity(0.9)
            VStack(spacing: 30) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                
                Text("Playback Failed")
                    .font(CinemeltTheme.fontTitle(40))
                    .foregroundColor(CinemeltTheme.cream)
                
                Text(viewModel.errorMessage ?? "Unknown Error")
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                
                Button("Close") {
                    viewModel.cleanup()
                    onBack()
                }
                .buttonStyle(CinemeltCardButtonStyle())
                .padding(.top, 20)
            }
            .padding(60)
            .background(CinemeltTheme.charcoal)
            .cornerRadius(30)
        }
    }
    
    // Formatting Helper
    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite { return "--:--" }
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Version Selection Overlay (NEW)
struct VersionSelectionOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    var onClose: () -> Void
    @FocusState private var focusedVersion: String?
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Select Version")
                    .font(CinemeltTheme.fontTitle(40))
                    .foregroundColor(CinemeltTheme.cream)
                    .cinemeltGlow()
                
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(viewModel.alternativeVersions, id: \.url) { channel in
                            Button(action: { viewModel.switchVersion(channel) }) {
                                HStack {
                                    Text(channel.quality ?? "Unknown Quality")
                                        .font(CinemeltTheme.fontTitle(24))
                                        .foregroundColor(.white)
                                    Spacer()
                                    if channel.url == viewModel.currentUrl {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(CinemeltTheme.accent)
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedVersion, equals: channel.url)
                        }
                    }
                    .padding(40)
                }
                .frame(width: 500, height: 600)
            }
        }
        .onExitCommand { onClose() }
    }
}

// MARK: - Track Selection Overlay
struct TrackSelectionOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    var onClose: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            HStack(alignment: .top, spacing: 100) {
                
                // Audio Column
                trackColumn(title: "Audio", tracks: viewModel.audioTracks, currentIndex: viewModel.currentAudioIndex) { i in
                    viewModel.setAudioTrack(index: i)
                }
                
                // Subtitle Column
                trackColumn(title: "Subtitles", tracks: viewModel.subtitleTracks, currentIndex: viewModel.currentSubtitleIndex) { i in
                    viewModel.setSubtitleTrack(index: i)
                }
                
            }
            .frame(height: 600)
        }
        // Menu button to close overlay
        .onExitCommand {
            onClose()
        }
    }
    
    private func trackColumn(title: String, tracks: [String], currentIndex: Int, action: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.accent)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if tracks.isEmpty {
                        Text("No tracks found")
                            .font(CinemeltTheme.fontBody(20))
                            .foregroundColor(.gray)
                    } else {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                            Button(action: { action(index) }) {
                                HStack {
                                    Text(track)
                                        .font(CinemeltTheme.fontBody(22))
                                        .foregroundColor(.white)
                                    Spacer()
                                    if index == currentIndex {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(CinemeltTheme.accent)
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                        }
                    }
                }
            }
        }
        .frame(width: 400)
    }
}

// MARK: - Auto Play Overlay
struct AutoPlayOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    @FocusState private var isPlayNowFocused: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            HStack(spacing: 60) {
                // Info
                VStack(alignment: .leading, spacing: 20) {
                    Text("Up Next")
                        .font(CinemeltTheme.fontBody(28))
                        .foregroundColor(.gray)
                    
                    if let next = viewModel.nextEpisode {
                        Text(next.title)
                            .font(CinemeltTheme.fontTitle(50))
                            .foregroundColor(CinemeltTheme.cream)
                            .lineLimit(2)
                            .cinemeltGlow()
                    }
                    
                    HStack(spacing: 15) {
                        Image(systemName: "timer")
                            .foregroundColor(CinemeltTheme.accent)
                        Text("Playing in \(viewModel.autoPlayCounter) seconds")
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(CinemeltTheme.accent)
                            .monospacedDigit()
                    }
                }
                .frame(width: 500)
                
                // Actions
                VStack(spacing: 20) {
                    Button(action: { viewModel.confirmAutoPlay() }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play Now")
                        }
                        .font(CinemeltTheme.fontTitle(28))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 20)
                        .background(CinemeltTheme.accent)
                        .cornerRadius(16)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                    .focused($isPlayNowFocused)
                    
                    Button(action: { viewModel.cancelAutoPlay() }) {
                        Text("Cancel")
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                }
            }
        }
        .onAppear {
            isPlayNowFocused = true
        }
    }
}

// MARK: - Mini Details Overlay
struct MiniDetailsOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    let channel: Channel
    var onPlayNext: () -> Void
    var onClose: () -> Void
    
    @FocusState private var focusedButton: String?
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(alignment: .bottom, spacing: 40) {
                
                // 1. Poster / Thumbnail
                AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.1))
                }
                .frame(width: 200, height: 300)
                .cornerRadius(12)
                .shadow(radius: 20)
                
                // 2. Info Block
                VStack(alignment: .leading, spacing: 10) {
                    Text(channel.title)
                        .font(CinemeltTheme.fontTitle(50))
                        .foregroundColor(CinemeltTheme.cream)
                        .lineLimit(2)
                    
                    // Metadata Row
                    HStack(spacing: 15) {
                        Badge(text: channel.quality ?? "HD")
                        Badge(text: channel.type.capitalized)
                        if !viewModel.videoRating.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(CinemeltTheme.accent)
                                    .font(.caption)
                                Text(viewModel.videoRating)
                                    .font(CinemeltTheme.fontBody(20))
                                    .foregroundColor(CinemeltTheme.cream)
                            }
                        }
                        if !viewModel.videoYear.isEmpty {
                            Text(viewModel.videoYear)
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(.gray)
                        }
                        if let dur = viewModel.duration as Double?, dur > 0 {
                            Text("\(Int(dur / 60)) min")
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Synopsis
                    if !viewModel.videoOverview.isEmpty {
                        Text(viewModel.videoOverview)
                            .font(CinemeltTheme.fontBody(20))
                            .foregroundColor(.gray)
                            .lineLimit(3)
                    }
                    
                    // Disclaimer / Help
                    Text("Swipe Up or Press Menu to close")
                        .font(CinemeltTheme.fontBody(18))
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 3. Actions Block (Right Side)
                VStack(alignment: .leading, spacing: 15) {
                    
                    Text("Playback Controls")
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 20) {
                        // Play Next (Logic: Replaces Restart if next episode exists)
                        if viewModel.canPlayNext {
                            Button(action: onPlayNext) {
                                HStack {
                                    Image(systemName: "forward.end.fill")
                                        .font(.headline)
                                    VStack(alignment: .leading) {
                                        Text("Next Episode")
                                            .font(CinemeltTheme.fontTitle(24))
                                            .foregroundColor(.black)
                                        if let next = viewModel.nextEpisode {
                                            Text(next.title) // e.g. "S01 E02"
                                                .font(.caption)
                                                .foregroundColor(.black.opacity(0.7))
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 15)
                                .background(CinemeltTheme.accent)
                                .cornerRadius(12)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedButton, equals: "next")
                        } else {
                            // Standard Restart Button
                            Button(action: { viewModel.restartPlayback() }) {
                                VStack(spacing: 5) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.headline)
                                    Text("Restart")
                                        .font(.caption)
                                }
                                .frame(width: 100, height: 70)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedButton, equals: "restart")
                        }
                    }
                    
                    Text("Speed")
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.gray)
                        .padding(.top, 10)
                    
                    // Speed Control
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                                Button(action: { viewModel.setPlaybackSpeed(Float(speed)) }) {
                                    Text("\(String(format: "%g", speed))x")
                                        .font(CinemeltTheme.fontBody(20))
                                        .frame(width: 60, height: 40)
                                        .foregroundColor(viewModel.playbackRate == Float(speed) ? .black : .white)
                                        .background(viewModel.playbackRate == Float(speed) ? CinemeltTheme.accent : Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                                .focused($focusedButton, equals: "speed_\(speed)")
                            }
                        }
                        .padding(10) // Padding for focus expansion
                    }
                    .frame(width: 500, height: 100)
                }
                .frame(width: 600)
            }
            .padding(50)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [CinemeltTheme.charcoal, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        ).opacity(0.8)
                    )
                    .ignoresSafeArea()
            )
            .frame(height: 450) // Approx 1/3 to 1/2 screen
            .cornerRadius(40, corners: [.topLeft, .topRight])
            .shadow(radius: 50)
        }
        .onExitCommand { onClose() }
        .onAppear {
            // Default focus to next/restart button when opened
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedButton = viewModel.canPlayNext ? "next" : "restart"
            }
        }
    }
}

// MARK: - Extracted Controls View
struct ControlsOverlayView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let channel: Channel
    var focusedField: FocusState<PlayerView.PlayerFocus?>.Binding
    var onShowTracks: () -> Void
    var onShowVersions: () -> Void // NEW Action
    
    var body: some View {
        ZStack {
            // Gradient Backdrop
            LinearGradient(
                colors: [.black.opacity(0.9), .clear, .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack {
                // --- TOP BAR (Upper Controls Zone) ---
                HStack(alignment: .top) {
                    // Title Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.videoTitle)
                            .font(CinemeltTheme.fontTitle(42))
                            .foregroundColor(CinemeltTheme.cream)
                            .shadow(color: .black, radius: 2)
                        
                        HStack(spacing: 12) {
                            Badge(text: viewModel.qualityBadge)
                            if !viewModel.videoRating.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(CinemeltTheme.accent)
                                        .font(.caption)
                                    Text(viewModel.videoRating)
                                        .font(CinemeltTheme.fontBody(20))
                                        .foregroundColor(CinemeltTheme.cream)
                                }
                            }
                            if !viewModel.videoYear.isEmpty {
                                Text(viewModel.videoYear)
                                    .font(CinemeltTheme.fontBody(20))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    Spacer()
                    
                    // FOCUS FIX: Group buttons together for easier navigation
                    HStack(spacing: 20) {
                        // Versions Button (Only if alternatives exist)
                        if !viewModel.alternativeVersions.isEmpty {
                            Button(action: onShowVersions) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.title)
                                    .padding(15)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.card) // Use standard style for focus effect
                        }
                        
                        // Tracks Button
                        Button(action: onShowTracks) {
                            Image(systemName: "captions.bubble.fill")
                                .font(.title)
                                .padding(15)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.card)
                        
                        // Favorite Button
                        Button(action: { viewModel.toggleFavorite() }) {
                            HStack(spacing: 10) {
                                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                    .font(.title3)
                                if focusedField.wrappedValue == .upperControls {
                                    Text(viewModel.isFavorite ? "Saved" : "Favorite")
                                        .font(CinemeltTheme.fontBody(20))
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(focusedField.wrappedValue == .upperControls ? CinemeltTheme.accent : Color.white.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain) // This one uses custom styling logic
                    }
                    // FOCUS FIX: Define this group as a focus section
                    .focusSection()
                    .focused(focusedField, equals: .upperControls)
                    .onMoveCommand { direction in
                        if direction == .down {
                            focusedField.wrappedValue = .videoSurface
                        }
                    }
                }
                .padding(60)
                
                Spacer()
                
                // --- CENTER STATUS ---
                if !viewModel.isPlaying && !viewModel.isBuffering && !viewModel.isError {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 150))
                        .foregroundColor(CinemeltTheme.accent.opacity(0.8))
                        .shadow(color: .black.opacity(0.5), radius: 20)
                }
                
                Spacer()
                
                // --- BOTTOM BAR (Visual Only - Controlled by VideoSurface Focus) ---
                VStack(spacing: 20) {
                    HStack(spacing: 30) {
                        // Current Time
                        Text(formatTime(viewModel.currentTime))
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(CinemeltTheme.accent)
                            .monospacedDigit()
                        
                        // Progress Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Track
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 12)
                                
                                // Fill
                                if viewModel.duration > 0 {
                                    let width = (viewModel.currentTime / viewModel.duration) * geo.size.width
                                    Capsule()
                                        .fill(CinemeltTheme.accent)
                                        .frame(width: max(0, min(geo.size.width, width)), height: 12)
                                        // Glow when playhead is active
                                        .shadow(
                                            color: CinemeltTheme.accent.opacity(focusedField.wrappedValue == .videoSurface ? 0.8 : 0.3),
                                            radius: focusedField.wrappedValue == .videoSurface ? 10 : 0
                                        )
                                }
                                
                                // Scrub Knob (Visual indicator of focus)
                                if focusedField.wrappedValue == .videoSurface && viewModel.duration > 0 {
                                    let width = (viewModel.currentTime / viewModel.duration) * geo.size.width
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 24, height: 24)
                                        .offset(x: max(0, min(geo.size.width, width)) - 12)
                                        .shadow(color: .black.opacity(0.5), radius: 2)
                                }
                            }
                        }
                        .frame(height: 12)
                        
                        // Duration
                        Text(formatTime(viewModel.duration))
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(CinemeltTheme.cream)
                            .monospacedDigit()
                    }
                    
                    // Hints
                    if focusedField.wrappedValue == .videoSurface {
                        HStack(spacing: 15) {
                            HintItem(icon: "arrow.left.and.right.circle.fill", text: "Scrub")
                            HintItem(icon: "arrow.down.circle.fill", text: "Info & Speed")
                            HintItem(icon: "arrow.up.circle.fill", text: "Tracks & Options")
                        }
                        .transition(.opacity)
                    }
                }
                .padding(60)
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite { return "--:--" }
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Helper Views & Bridges

struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(CinemeltTheme.fontBody(16))
            .fontWeight(.bold)
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CinemeltTheme.accent)
            .cornerRadius(4)
    }
}

struct HintItem: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(CinemeltTheme.fontBody(18))
        }
        .foregroundColor(.white.opacity(0.5))
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - VLC Bridge
struct VLCVideoSurface: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerViewModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        viewModel.assignView(view)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Siri Remote Swipe Handler
struct SiriRemoteSwipeHandler: UIViewRepresentable {
    // Returns X (Horizontal) and Y (Vertical) translation
    var onPan: (CGFloat, CGFloat) -> Void
    var onEnd: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(panGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPan: onPan, onEnd: onEnd)
    }
    
    class Coordinator: NSObject {
        var onPan: (CGFloat, CGFloat) -> Void
        var onEnd: () -> Void
        
        init(onPan: @escaping (CGFloat, CGFloat) -> Void, onEnd: @escaping () -> Void) {
            self.onPan = onPan
            self.onEnd = onEnd
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .changed {
                let translation = gesture.translation(in: gesture.view)
                onPan(translation.x, translation.y)
            } else if gesture.state == .ended || gesture.state == .cancelled {
                onEnd()
            }
        }
    }
}
