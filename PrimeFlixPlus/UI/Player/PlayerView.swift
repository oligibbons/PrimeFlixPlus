import SwiftUI
import TVVLCKit

struct PlayerView: View {
    let channel: Channel
    let onBack: () -> Void
    var onPlayChannel: ((Channel) -> Void)? = nil
    
    @StateObject private var viewModel = PlayerViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // MARK: - Focus State
    // Public so sub-overlays can bind to it
    enum PlayerFocus: Hashable {
        case videoSurface       // The "Playhead" / Scrubbing Zone
        case upperControls      // Top Bar Buttons
        case miniDetails        // Swipe-Down overlay
        case autoPlayOverlay    // Timer Overlay
        case trackSelection     // Audio/Subtitle selection
        case versionSelection   // Quality selection
    }
    
    @FocusState private var focusedField: PlayerFocus?
    
    // Helper to determine if we should lock standard controls
    private var areOverlaysActive: Bool {
        viewModel.showMiniDetails ||
        viewModel.showAutoPlay ||
        viewModel.showTrackSelection ||
        viewModel.showVersionSelection
    }
    
    var body: some View {
        ZStack {
            // 0. Background
            Color.black.ignoresSafeArea()
            
            GeometryReader { geo in
                ZStack {
                    // 1. Video Surface (Base Layer)
                    VLCVideoSurface(viewModel: viewModel)
                        .ignoresSafeArea()
                    
                    // 2. Interaction Layer (Gestures & Focus)
                    interactionLayer(geo: geo)
                }
            }
            
            // 3. Status Views (Buffering, Scrubbing, Error)
            statusLayers
            
            // 4. Overlays
            overlaysLayer
            
            // 5. Controls (Top/Bottom Bars)
            if viewModel.showControls && !areOverlaysActive {
                ControlsOverlayView(
                    viewModel: viewModel,
                    channel: channel,
                    focusedField: $focusedField,
                    onShowTracks: {
                        withAnimation { viewModel.showTrackSelection = true }
                        focusedField = .trackSelection
                    },
                    onShowVersions: {
                        withAnimation { viewModel.showVersionSelection = true }
                        focusedField = .versionSelection
                    }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .onAppear {
            viewModel.configure(repository: repository, channel: channel)
            // Force initial focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .videoSurface
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PlayNextEpisode"))) { note in
            if let nextChannel = note.object as? Channel {
                viewModel.cleanup()
                onPlayChannel?(nextChannel)
            }
        }
        // Auto-focus logic when controls appear/disappear
        .onChange(of: viewModel.showControls) { show in
            if show && !areOverlaysActive {
                focusedField = .videoSurface
            }
        }
        // Handle focus navigation to Upper Controls
        .onChange(of: focusedField) { focus in
            if focus == .upperControls {
                viewModel.triggerControls(forceShow: true)
            }
        }
    }
    
    // MARK: - Subviews & Layers
    
    private func interactionLayer(geo: GeometryProxy) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable(!areOverlaysActive)
            .focused($focusedField, equals: .videoSurface)
            
            // Gestures
            .background(
                SiriRemoteSwipeHandler(
                    onPan: { x, y in
                        guard !areOverlaysActive else { return }
                        
                        // Horizontal: Scrub
                        if abs(x) > abs(y) {
                            viewModel.startScrubbing(translation: x, screenWidth: geo.size.width)
                        }
                        // Vertical Down: Show Mini Details
                        else if y > 50 {
                            withAnimation {
                                viewModel.showMiniDetails = true
                                focusedField = .miniDetails
                            }
                        }
                    },
                    onEnd: {
                        if !areOverlaysActive {
                            viewModel.endScrubbing()
                        }
                    }
                )
            )
            
            // D-Pad / Remote Clicks
            .onMoveCommand { direction in
                guard !areOverlaysActive else { return }
                
                viewModel.triggerControls(forceShow: true)
                
                switch direction {
                case .left: viewModel.seekBackward()
                case .right: viewModel.seekForward()
                case .up:
                    if viewModel.showControls {
                        focusedField = .upperControls
                    } else {
                        viewModel.triggerControls(forceShow: true)
                    }
                case .down:
                    withAnimation {
                        viewModel.showMiniDetails = true
                        focusedField = .miniDetails
                    }
                @unknown default: break
                }
            }
            .onPlayPauseCommand {
                if !areOverlaysActive { viewModel.togglePlayPause() }
            }
            .onExitCommand {
                print("🔙 Menu Pressed on Playhead - Exiting")
                viewModel.cleanup()
                onBack()
            }
    }
    
    @ViewBuilder
    private var statusLayers: some View {
        // Buffering
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
        
        // Scrubbing Preview
        if viewModel.isScrubbing {
            VStack {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .frame(width: 280, height: 180)
                        .shadow(radius: 20)
                    
                    AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.black }
                    .frame(width: 280, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .opacity(0.6)
                    
                    Text(PlayerTimeFormatter.string(from: viewModel.currentTime))
                        .font(CinemeltTheme.fontTitle(40))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 5)
                }
                .padding(.bottom, 120)
                .transition(.opacity)
            }
        }
        
        // Error
        if viewModel.isError {
            errorOverlay
        }
    }
    
    @ViewBuilder
    private var overlaysLayer: some View {
        // 1. Mini Details
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
                    withAnimation { viewModel.showMiniDetails = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = .videoSurface
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(50)
            .focusSection()
            .focused($focusedField, equals: .miniDetails)
        }
        
        // 2. Track Selection
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
            .onAppear { focusedField = .trackSelection }
            .focused($focusedField, equals: .trackSelection)
        }
        
        // 3. Version Selection
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
            .onAppear { focusedField = .versionSelection }
            .focused($focusedField, equals: .versionSelection)
        }
        
        // 4. Auto Play
        if viewModel.showAutoPlay {
            AutoPlayOverlay(viewModel: viewModel)
                .zIndex(60)
                .focusSection()
                .onAppear { focusedField = .autoPlayOverlay }
                .focused($focusedField, equals: .autoPlayOverlay)
        }
    }
    
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
}

