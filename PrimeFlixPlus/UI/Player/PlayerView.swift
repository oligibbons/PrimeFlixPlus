import SwiftUI
import TVVLCKit

struct PlayerView: View {
    let channel: Channel
    let onBack: () -> Void
    var onPlayChannel: ((Channel) -> Void)? = nil
    
    @StateObject private var viewModel = PlayerViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // Focus Management
    enum PlayerFocus: Hashable {
        case videoSurface
        case upperControls
        case miniDetails
        case autoPlayOverlay
        case trackSelection
        case versionSelection
    }
    
    @FocusState private var focusedField: PlayerFocus?
    
    private var areOverlaysActive: Bool {
        viewModel.showMiniDetails ||
        viewModel.showAutoPlay ||
        viewModel.showTrackSelection ||
        viewModel.showVersionSelection
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geo in
                ZStack {
                    // 1. Video Surface
                    VLCVideoSurface(viewModel: viewModel)
                        .ignoresSafeArea()
                    
                    // 2. Interaction Layer
                    interactionLayer(geo: geo)
                }
            }
            
            // 3. Status & Overlays
            statusLayers
            overlaysLayer
            
            // 4. Controls
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
        .onChange(of: viewModel.showControls) { show in
            if show && !areOverlaysActive { focusedField = .videoSurface }
        }
    }
    
    private func interactionLayer(geo: GeometryProxy) -> some View {
        Color.clear
            .contentShape(Rectangle())
            // CRITICAL: Always allow focus unless a modal overlay is blocking
            .focusable(!areOverlaysActive)
            .focused($focusedField, equals: .videoSurface)
            .background(
                SiriRemoteSwipeHandler(
                    onPan: { x, y in
                        guard !areOverlaysActive else { return }
                        if abs(x) > abs(y) {
                            // Horizontal Scrub
                            viewModel.startScrubbing(translation: x, screenWidth: geo.size.width)
                        } else if y > 50 {
                            // Swipe Down for Mini Details
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
            .onMoveCommand { direction in
                guard !areOverlaysActive else { return }
                viewModel.triggerControls(forceShow: true)
                
                switch direction {
                case .left: viewModel.seekBackward()
                case .right: viewModel.seekForward()
                case .up:
                    if viewModel.showControls { focusedField = .upperControls }
                    else { viewModel.triggerControls(forceShow: true) }
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
                    CinemeltLoadingIndicator()
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
                        .frame(width: 320, height: 200)
                        .shadow(radius: 20)
                    
                    if let poster = viewModel.posterImage {
                        AsyncImage(url: poster) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { Color.black }
                        .frame(width: 320, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .opacity(0.5)
                    }
                    
                    VStack {
                        Image(systemName: "arrow.left.and.right.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(CinemeltTheme.accent)
                        Text(PlayerTimeFormatter.string(from: viewModel.currentTime))
                            .font(CinemeltTheme.fontTitle(40))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 5)
                            .monospacedDigit()
                    }
                }
                .padding(.bottom, 120)
                .transition(.scale.combined(with: .opacity))
            }
        }
        
        if viewModel.isError {
            errorOverlay
        }
    }
    
    @ViewBuilder
    private var overlaysLayer: some View {
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
                    focusedField = .videoSurface
                }
            )
            .zIndex(50)
            .focused($focusedField, equals: .miniDetails)
        }
        
        if viewModel.showTrackSelection {
            TrackSelectionOverlay(
                viewModel: viewModel,
                onClose: {
                    withAnimation { viewModel.showTrackSelection = false }
                    focusedField = .videoSurface
                }
            )
            .zIndex(55)
            .focused($focusedField, equals: .trackSelection)
        }
        
        if viewModel.showVersionSelection {
            VersionSelectionOverlay(
                viewModel: viewModel,
                onClose: {
                    withAnimation { viewModel.showVersionSelection = false }
                    focusedField = .videoSurface
                }
            )
            .zIndex(56)
            .focused($focusedField, equals: .versionSelection)
        }
        
        if viewModel.showAutoPlay {
            AutoPlayOverlay(viewModel: viewModel)
                .zIndex(60)
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
                Button("Close") {
                    viewModel.cleanup()
                    onBack()
                }
                .buttonStyle(CinemeltCardButtonStyle())
            }
            .padding(60)
            .background(CinemeltTheme.charcoal)
            .cornerRadius(30)
        }
    }
}
