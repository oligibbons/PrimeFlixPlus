import SwiftUI

struct ControlsOverlayView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let channel: Channel
    
    // Binding to parent focus state
    var focusedField: FocusState<PlayerView.PlayerFocus?>.Binding
    
    // Actions
    var onShowTracks: () -> Void
    var onShowVersions: () -> Void
    var onShowSettings: () -> Void
    
    // MARK: - Internal Focus Management
    // We use a local enum to manage focus precisely between buttons,
    // ensuring the focus engine doesn't "fall through" to the background layer.
    private enum UpperControl: Hashable {
        case settings
        case versions
        case tracks
        case favorite
    }
    
    @FocusState private var upperControlFocus: UpperControl?
    @FocusState private var internalFocus: Bool // Keep-alive tracker
    
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
                    
                    // 1. Title & Metadata (Restored full UI)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.videoTitle)
                            .font(CinemeltTheme.fontTitle(42))
                            .foregroundColor(CinemeltTheme.cream)
                            .shadow(color: .black, radius: 2)
                            .lineLimit(1)
                        
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
                            
                            if viewModel.audioDelay != 0 {
                                Text("Audio: \(viewModel.audioDelay)ms")
                                    .font(CinemeltTheme.fontBody(18))
                                    .foregroundColor(CinemeltTheme.accent)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // 2. Button Group
                    HStack(spacing: 20) {
                        
                        // Settings Button
                        Button(action: onShowSettings) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .padding(12)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.card)
                        .focused($upperControlFocus, equals: .settings)
                        .focused($internalFocus)
                        
                        // Versions Button
                        if !viewModel.alternativeVersions.isEmpty {
                            Button(action: onShowVersions) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.title2)
                                    .padding(12)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.card)
                            .focused($upperControlFocus, equals: .versions)
                            .focused($internalFocus)
                        }
                        
                        // Tracks Button
                        Button(action: onShowTracks) {
                            Image(systemName: "captions.bubble.fill")
                                .font(.title2)
                                .padding(12)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.card)
                        .focused($upperControlFocus, equals: .tracks)
                        .focused($internalFocus)
                        
                        // Favorite Button
                        Button(action: { viewModel.toggleFavorite() }) {
                            Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                .font(.title2)
                                .foregroundColor(viewModel.isFavorite ? CinemeltTheme.accent : .white)
                                .padding(12)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.card)
                        .focused($upperControlFocus, equals: .favorite)
                        .focused($internalFocus)
                    }
                    .focusSection() // CRITICAL: Tells tvOS "Keep focus here when moving left/right"
                    .onMoveCommand { direction in
                        if direction == .down {
                            // Only exit top bar on explicit DOWN command
                            focusedField.wrappedValue = .videoSurface
                            upperControlFocus = nil
                        }
                    }
                }
                .padding(.top, 60)
                .padding(.horizontal, 60)
                
                Spacer()
                
                // --- CENTER STATUS ---
                if !viewModel.isPlaying && !viewModel.isBuffering && !viewModel.isError && !viewModel.isScrubbing {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 140))
                        .foregroundColor(CinemeltTheme.accent.opacity(0.8))
                        .shadow(color: .black.opacity(0.5), radius: 20)
                }
                
                Spacer()
                
                // --- BOTTOM BAR ---
                VStack(spacing: 20) {
                    HStack(spacing: 30) {
                        Text(PlayerTimeFormatter.string(from: viewModel.currentTime))
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(CinemeltTheme.accent)
                            .monospacedDigit()
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 12)
                                
                                if viewModel.duration > 0 {
                                    let width = (viewModel.currentTime / viewModel.duration) * geo.size.width
                                    Capsule()
                                        .fill(CinemeltTheme.accent)
                                        .frame(width: max(0, min(geo.size.width, width)), height: 12)
                                }
                            }
                        }
                        .frame(height: 12)
                        
                        Text(PlayerTimeFormatter.string(from: viewModel.duration))
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(CinemeltTheme.cream)
                            .monospacedDigit()
                    }
                    
                    if focusedField.wrappedValue == .videoSurface {
                        HStack(spacing: 15) {
                            HintItem(icon: "arrow.left.and.right.circle.fill", text: "Scrub")
                            HintItem(icon: "arrow.down.circle.fill", text: "Info")
                            HintItem(icon: "arrow.up.circle.fill", text: "Controls")
                        }
                        .transition(.opacity)
                    }
                }
                .padding(60)
            }
        }
        // MARK: - Focus Synchronization
        // 1. Sync: Parent -> Local
        // When parent says "Focus Upper Controls", we force focus to the Settings button
        .onChange(of: focusedField.wrappedValue) { newValue in
            if newValue == .upperControls {
                // Only reset to Settings if we aren't already focused on a button
                if upperControlFocus == nil {
                    upperControlFocus = .settings
                }
            }
        }
        // 2. Keep controls alive while navigating top bar
        .onChange(of: internalFocus) { isFocused in
            if isFocused {
                viewModel.triggerControls(forceShow: true)
            }
        }
    }
}
