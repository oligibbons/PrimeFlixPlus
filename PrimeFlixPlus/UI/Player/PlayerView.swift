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
        case videoSurface   // The scrubber/play bar
        
        // Overlays (Modals)
        case miniDetails
        case autoPlayOverlay
        case trackSelection
        case versionSelection
        case videoSettings
        case resumePrompt
        
        // NEW: Favorites Prompt
        case favoritesPrompt
    }
    
    @FocusState private var focusedField: PlayerFocus?
    
    private var areOverlaysActive: Bool {
        viewModel.showMiniDetails ||
        viewModel.showAutoPlay ||
        viewModel.showTrackSelection ||
        viewModel.showVersionSelection ||
        viewModel.showVideoSettings ||
        viewModel.showResumePrompt ||
        viewModel.showFavoritesPrompt // Added
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
            
            // 4. Controls (Now OSD Only)
            if viewModel.showControls && !areOverlaysActive {
                ControlsOverlayView(
                    viewModel: viewModel,
                    channel: channel,
                    focusedField: $focusedField
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .onAppear {
            viewModel.configure(repository: repository, channel: channel)
            
            // Force focus to surface on load to prevent getting stuck
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if focusedField == nil {
                    focusedField = .videoSurface
                }
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
        // CENTRALIZED EXIT COMMAND
        .onExitCommand {
            handleExit()
        }
    }
    
    // MARK: - Centralized Logic
    
    private func handleExit() {
        if areOverlaysActive {
            // Priority 1: Close any open modals
            withAnimation {
                viewModel.showMiniDetails = false
                viewModel.showTrackSelection = false
                viewModel.showVersionSelection = false
                viewModel.showVideoSettings = false
                viewModel.showResumePrompt = false
                viewModel.showAutoPlay = false
                viewModel.showFavoritesPrompt = false // Added
            }
            // Return focus to the scrubber
            focusedField = .videoSurface
        } else if viewModel.showControls {
            // Priority 2: If Controls visible (OSD), hide them
            withAnimation {
                viewModel.showControls = false
            }
        } else {
            // Priority 3: Actual Back Navigation
            viewModel.cleanup()
            onBack()
        }
    }
    
    private func interactionLayer(geo: GeometryProxy) -> some View {
        // FIX: Use nearly-invisible black instead of clear to ensure focus engine hit-testing works reliably
        Color.black.opacity(0.001)
            .contentShape(Rectangle())
            // Only focusable if we aren't showing a modal overlay
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
                case .down:
                    // Down -> Open Mini Details
                    withAnimation {
                        viewModel.showMiniDetails = true
                        focusedField = .miniDetails
                    }
                case .up:
                    // Up -> Just wake up OSD controls, no focus change
                    viewModel.triggerControls(forceShow: true)
                @unknown default: break
                }
            }
            .onPlayPauseCommand {
                if !areOverlaysActive { viewModel.togglePlayPause() }
            }
    }
    
    @ViewBuilder
    private var statusLayers: some View {
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
                },
                // NEW: Connect Buttons to Overlays
                onShowTracks: {
                    withAnimation { viewModel.showTrackSelection = true }
                    focusedField = .trackSelection
                },
                onShowVersions: {
                    withAnimation { viewModel.showVersionSelection = true }
                    focusedField = .versionSelection
                },
                onShowSettings: {
                    withAnimation { viewModel.showVideoSettings = true }
                    focusedField = .videoSettings
                },
                onToggleFavorite: {
                    viewModel.toggleFavorite()
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
        
        // NEW: Video Settings Overlay
        if viewModel.showVideoSettings {
            VideoSettingsOverlay(
                viewModel: viewModel,
                onClose: {
                    withAnimation { viewModel.showVideoSettings = false }
                    focusedField = .videoSurface
                }
            )
            .zIndex(57)
            .focused($focusedField, equals: .videoSettings)
        }
        
        if viewModel.showResumePrompt {
            ResumePromptOverlay(viewModel: viewModel)
                .zIndex(58)
                .focused($focusedField, equals: .resumePrompt)
        }
        
        if viewModel.showAutoPlay {
            AutoPlayOverlay(viewModel: viewModel)
                .zIndex(60)
                .focused($focusedField, equals: .autoPlayOverlay)
        }
        
        // NEW: Favorites Prompt (Triggers at End of Playback)
        if viewModel.showFavoritesPrompt {
            FavoritesPromptOverlay(
                title: viewModel.videoTitle,
                onAdd: {
                    viewModel.toggleFavorite()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation { viewModel.showFavoritesPrompt = false }
                        focusedField = .videoSurface
                    }
                },
                onDismiss: {
                    withAnimation { viewModel.showFavoritesPrompt = false }
                    focusedField = .videoSurface
                }
            )
            .zIndex(61)
            .focused($focusedField, equals: .favoritesPrompt)
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

// MARK: - Helper: Favorites Prompt Overlay
struct FavoritesPromptOverlay: View {
    let title: String
    let onAdd: () -> Void
    let onDismiss: () -> Void
    
    @FocusState private var focusedAction: FocusAction?
    
    enum FocusAction {
        case add
        case cancel
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Icon
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(CinemeltTheme.accent)
                    .shadow(color: CinemeltTheme.accent.opacity(0.6), radius: 20)
                
                // Text
                VStack(spacing: 15) {
                    Text("Add to My List?")
                        .font(CinemeltTheme.fontTitle(48))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                    
                    Text("Enjoyed watching \"\(title)\"?")
                        .font(CinemeltTheme.fontBody(28))
                        .foregroundColor(.gray)
                    
                    Text("Add it to your favorites for better recommendations.")
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // Buttons
                HStack(spacing: 60) {
                    Button(action: onDismiss) {
                        Text("No Thanks")
                            .font(CinemeltTheme.fontBody(28))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 20)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                    .focused($focusedAction, equals: .cancel)
                    
                    Button(action: onAdd) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add to Favorites")
                        }
                        .font(CinemeltTheme.fontTitle(28))
                        .foregroundColor(.black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 20)
                        .background(CinemeltTheme.accent)
                        .cornerRadius(16)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                    .focused($focusedAction, equals: .add)
                }
            }
            .padding(80)
            .background(.ultraThinMaterial)
            .cornerRadius(40)
            .overlay(
                RoundedRectangle(cornerRadius: 40)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(radius: 50)
        }
        .onAppear {
            // Default focus to "Add" for convenience
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedAction = .add
            }
        }
    }
}
