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
            
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                    .onDisappear {
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                    .overlay(controlsOverlay)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2.0)
            }
        }
        // MARK: - Interaction Handling
        .onMoveCommand { _ in viewModel.triggerControls() }
        .onPlayPauseCommand { viewModel.togglePlayPause() }
        .onExitCommand {
            // Intercept Menu button to close player gracefully
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
                Color.black.opacity(0.4).ignoresSafeArea()
                
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
                    
                    // Big Play Icon
                    if !viewModel.isPlaying {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 100))
                            .foregroundColor(.white.opacity(0.8))
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
                                .foregroundColor(.gray)
                            
                            // Progress Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 8)
                                        .cornerRadius(4)
                                    
                                    Rectangle()
                                        .fill(Color.cyan)
                                        .frame(width: viewModel.duration > 0 ?
                                               geo.size.width * (viewModel.currentTime / viewModel.duration) : 0,
                                               height: 8)
                                        .cornerRadius(4)
                                }
                            }
                            .frame(height: 8)
                            
                            Text(formatTime(viewModel.duration))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(60)
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite { return "00:00" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "00:00"
    }
}
