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
                    // CRITICAL FIX: .focusable(!showMiniDetails) disables this layer when overlay is open,
                    // forcing focus to the Overlay instead of the Player.
                    Color.clear
                        .contentShape(Rectangle())
                        .focusable(!viewModel.showMiniDetails)
                        .focused($focusedField, equals: .videoSurface)
                        
                        // --- GESTURES ---
                        // Handles both Horizontal (Scrub) and Vertical (Overlay) swipes
                        .background(
                            SiriRemoteSwipeHandler(
                                onPan: { x, y in
                                    // LOCK: Disable scrubbing if Mini Details is open
                                    if viewModel.showMiniDetails { return }
                                    
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
                                    if !viewModel.showMiniDetails {
                                        viewModel.endScrubbing()
                                    }
                                }
                            )
                        )
                    
                        // Discrete Moves (D-Pad / Arrows)
                        .onMoveCommand { direction in
                            // LOCK: Do not allow player navigation if overlay is open
                            if viewModel.showMiniDetails { return }
                            
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
                            if !viewModel.showMiniDetails {
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
                        // Ideally we would fetch a frame here, but using cover art for context
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
            }
            
            // 7. Controls Overlay
            // We pass the focus binding down so the overlay knows if it's active
            if viewModel.showControls && !viewModel.showMiniDetails {
                ControlsOverlayView(
                    viewModel: viewModel,
                    channel: channel,
                    focusedField: $focusedField
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
        // Auto-Focus logic for Play/Pause state
        .onChange(of: viewModel.showControls) { show in
            // When controls appear (pause), default focus to playhead
            // When controls disappear (play), ensure focus stays on playhead
            // ONLY if overlay is closed
            if show && !viewModel.showMiniDetails {
                focusedField = .videoSurface
            }
        }
        // Logic to keep controls visible when navigating top buttons
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
                        // Play From Beginning
                        Button(action: { viewModel.restartPlayback() }) {
                            VStack(spacing: 5) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.headline) // Smaller icon per request
                                Text("Restart")
                                    .font(.caption)
                            }
                            .frame(width: 100, height: 70)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedButton, equals: "restart")
                        
                        // Play Next (if available)
                        if viewModel.canPlayNext {
                            Button(action: onPlayNext) {
                                VStack(spacing: 5) {
                                    Image(systemName: "forward.end.fill")
                                        .font(.headline) // Smaller icon per request
                                    Text("Next Ep")
                                        .font(.caption)
                                }
                                .frame(width: 100, height: 70)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedButton, equals: "next")
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
                                        .background(viewModel.playbackRate == Float(speed) ? CinemeltTheme.accent : Color.clear)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                                .focused($focusedButton, equals: "speed_\(speed)")
                            }
                        }
                        .padding(10) // Padding for focus growth
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
            // Default focus to restart button when opened
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedButton = "restart"
            }
        }
    }
}

// MARK: - Extracted Controls View
struct ControlsOverlayView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let channel: Channel
    var focusedField: FocusState<PlayerView.PlayerFocus?>.Binding
    
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
                        
                        if let q = channel.quality {
                            Text(q)
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(CinemeltTheme.accent)
                        }
                    }
                    Spacer()
                    
                    // Favorite Button (Focusable)
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
                    .buttonStyle(.plain) // Custom look defined above
                    .focused(focusedField, equals: .upperControls)
                    // Logic: Down Arrow -> Back to Playhead
                    .onMoveCommand { direction in
                        if direction == .down {
                            focusedField.wrappedValue = .videoSurface
                        }
                    }
                    // Logic: Menu Button -> Back to Playhead (Layer 1 Back)
                    .onExitCommand {
                        print("🔙 Menu on Controls -> Down to Playhead")
                        focusedField.wrappedValue = .videoSurface
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
                            HintItem(icon: "arrow.up.circle.fill", text: "Options")
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
