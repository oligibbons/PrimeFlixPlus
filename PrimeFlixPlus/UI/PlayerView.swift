// oligibbons/primeflixplus/PrimeFlixPlus-7315d01e01d1e889e041552206b1fb283d2eeb2d/PrimeFlixPlus/UI/PlayerView.swift

import SwiftUI
import TVVLCKit

struct PlayerView: View {
    let channel: Channel
    let onBack: () -> Void
    
    @StateObject private var viewModel = PlayerViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // MARK: - Focus State Logic
    enum PlayerFocus: Hashable {
        case videoSurface // The "Playhead" / Scrubbing Zone
        case upperControls // The Heart Button / Top Bar
    }
    @FocusState private var focusedField: PlayerFocus?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. VLC Video Surface (The "Playhead")
            // Acts as the base layer and default focus.
            VLCVideoSurface(viewModel: viewModel)
                .ignoresSafeArea()
                .focusable()
                .focused($focusedField, equals: .videoSurface)
                
                // Scrubbing Logic (Active only when this "Playhead" layer is focused)
                .onMoveCommand { direction in
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
                            // If controls are hidden, showing them usually defaults focus here anyway,
                            // but we can be explicit if needed.
                            viewModel.triggerControls(forceShow: true)
                        }
                    default:
                        break
                    }
                }
                .onPlayPauseCommand {
                    viewModel.togglePlayPause()
                }
                .onExitCommand {
                    // Standard Back behavior when on the playhead
                    print("🔙 Menu Pressed on Playhead - Exiting")
                    viewModel.cleanup()
                    onBack()
                }
            
            // 2. Buffering State
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
            
            // 3. Error State
            if viewModel.isError {
                errorOverlay
            }
            
            // 4. Controls Overlay
            // We pass the focus binding down so the overlay knows if it's active
            if viewModel.showControls {
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
            if show {
                // When paused/controls appear, DEFAULT to Playhead (VideoSurface)
                // This allows immediate scrubbing.
                focusedField = .videoSurface
            } else {
                // When controls hide, ensure focus stays on video to catch clicks
                focusedField = .videoSurface
            }
        }
        // Prevent controls from hiding while we are navigating the upper buttons
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
    
    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite { return "--:--" }
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Extracted Controls View
// Separated to keep the body clean and manage the "Upper Controls" focus logic cleanly.
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
                            HintItem(icon: "arrow.up.circle.fill", text: "Options")
                            HintItem(icon: "button.programmable", text: "Exit")
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

// Helper for hints
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

// MARK: - VLC Bridge
struct VLCVideoSurface: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerViewModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        viewModel.assignView(view)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // View updates handled by VM
    }
}
