import SwiftUI
import AVKit

struct PlayerView: View {
    let channel: Channel
    let onBack: () -> Void
    
    // Downgrade: Use @StateObject for ObservableObject logic
    @StateObject private var viewModel = PlayerViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player = viewModel.player {
                // Native Video Player Surface
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        // Prevent sleep during playback
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                    .onDisappear {
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                    .overlay(controlsOverlay)
            } else {
                ProgressView()
            }
        }
        // Custom Remote Handling
        .onMoveCommand { _ in viewModel.triggerControls() }
        .onPlayPauseCommand { viewModel.togglePlayPause() }
        .onExitCommand { onBack() }
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
                // Dimmed Background
                Color.black.opacity(0.4).ignoresSafeArea()
                
                VStack {
                    // Top Bar
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(60)
                    
                    Spacer()
                    
                    // Play/Pause Icon
                    if !viewModel.isPlaying {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 100))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Bottom Bar
                    VStack(alignment: .leading, spacing: 10) {
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
                                        .frame(height: 6)
                                        .cornerRadius(3)
                                    
                                    Rectangle()
                                        .fill(Color.cyan)
                                        .frame(width: viewModel.duration > 0 ?
                                               geo.size.width * (viewModel.currentTime / viewModel.duration) : 0,
                                               height: 6)
                                        .cornerRadius(3)
                                }
                            }
                            .frame(height: 6)
                            
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
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "00:00"
    }
}
