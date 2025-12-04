import SwiftUI
import AVKit

struct PlayerView: View {
    let channel: Channel
    let onBack: () -> Void
    
    @StateObject private var viewModel = PlayerViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. Video Surface
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                    .onDisappear {
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
            }
            
            // 2. Buffering / Loading
            if viewModel.player == nil || viewModel.isBuffering {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                            .scaleEffect(2.0)
                        
                        Text(viewModel.isBuffering ? "Buffering..." : "Connecting...")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            
            // 3. Error Overlay (Debug Info Included)
            if viewModel.isError {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text("Playback Error")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Error Message
                    Text(viewModel.errorMessage ?? "Unknown Error")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Divider().background(Color.gray)
                    
                    // DEBUG: Show the URL
                    VStack(spacing: 8) {
                        Text("DEBUG INFO:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.gray)
                        
                        Text(viewModel.currentUrl)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 40)
                    
                    Button("Close") {
                        viewModel.cleanup()
                        onBack()
                    }
                    .buttonStyle(.card)
                    .padding(.top, 20)
                }
                .padding(40)
                .background(Color(white: 0.15))
                .cornerRadius(20)
                .shadow(radius: 20)
                .frame(maxWidth: 800)
            }
            
            // 4. Controls
            controlsOverlay
        }
        .onMoveCommand { _ in viewModel.triggerControls() }
        .onPlayPauseCommand { viewModel.togglePlayPause() }
        .onExitCommand {
            viewModel.cleanup()
            onBack()
        }
        .onAppear {
            viewModel.configure(repository: repository, channel: channel)
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
    
    // MARK: - Overlay UI
    private var controlsOverlay: some View {
        ZStack {
            if viewModel.showControls || !viewModel.isPlaying {
                LinearGradient(colors: [.black.opacity(0.8), .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                
                VStack {
                    // Header
                    HStack {
                        Button(action: {
                            viewModel.cleanup()
                            onBack()
                        }) {
                            HStack {
                                Image(systemName: "arrow.left")
                                Text("Back")
                            }
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(60)
                    
                    Spacer()
                    
                    // Center Play
                    if !viewModel.isPlaying && !viewModel.isBuffering && !viewModel.isError {
                        Button(action: { viewModel.togglePlayPause() }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 100))
                                .foregroundColor(.white.opacity(0.8))
                                .shadow(radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    // Footer
                    VStack(alignment: .leading, spacing: 12) {
                        Text(viewModel.videoTitle)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        HStack(spacing: 20) {
                            Text(formatTime(viewModel.currentTime))
                                .font(.caption)
                                .foregroundColor(.cyan)
                                .monospacedDigit()
                            
                            // Progress Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 8)
                                        .cornerRadius(4)
                                    
                                    if viewModel.duration > 0 {
                                        Rectangle()
                                            .fill(Color.cyan)
                                            .frame(width: geo.size.width * (viewModel.currentTime / viewModel.duration), height: 8)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                            .frame(height: 8)
                            
                            Text(formatTime(viewModel.duration))
                                .font(.caption)
                                .foregroundColor(.gray)
                                .monospacedDigit()
                        }
                    }
                    .padding(60)
                }
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
