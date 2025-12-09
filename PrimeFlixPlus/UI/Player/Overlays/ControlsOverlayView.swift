import SwiftUI

struct ControlsOverlayView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let channel: Channel
    
    // Binding to parent focus state (Primary used to show/hide hints)
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
                // --- TOP BAR (Title & Metadata Only) ---
                HStack(alignment: .top) {
                    
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
                    
                    // Clock or Logo could go here
                    Image("CinemeltLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                        .opacity(0.5)
                }
                .padding(.top, 60)
                .padding(.horizontal, 60)
                
                Spacer()
                
                // --- CENTER STATUS ---
                // Only show if paused or special state
                if !viewModel.isPlaying && !viewModel.isBuffering && !viewModel.isError && !viewModel.isScrubbing {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 140))
                        .foregroundColor(CinemeltTheme.accent.opacity(0.8))
                        .shadow(color: .black.opacity(0.5), radius: 20)
                }
                
                Spacer()
                
                // --- BOTTOM BAR (Scrubber) ---
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
                            HintItem(icon: "arrow.down.circle.fill", text: "Info & Settings")
                        }
                        .transition(.opacity)
                    }
                }
                .padding(60)
            }
        }
    }
}
