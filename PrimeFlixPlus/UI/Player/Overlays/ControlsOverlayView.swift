import SwiftUI

struct ControlsOverlayView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let channel: Channel
    
    // We bind to the focus state of the parent (PlayerView) to coordinate focus movement
    var focusedField: FocusState<PlayerView.PlayerFocus?>.Binding
    
    var onShowTracks: () -> Void
    var onShowVersions: () -> Void
    
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
                    
                    // Button Group
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
                            .buttonStyle(.card)
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
                        .buttonStyle(.plain)
                    }
                    // Define this group as the .upperControls focus section
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
                        Text(PlayerTimeFormatter.string(from: viewModel.currentTime))
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
                        Text(PlayerTimeFormatter.string(from: viewModel.duration))
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
}

