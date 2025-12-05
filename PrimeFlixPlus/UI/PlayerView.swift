import SwiftUI
import TVVLCKit

struct PlayerView: View {
    let channel: Channel
    let onBack: () -> Void
    
    @StateObject private var viewModel = PlayerViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. VLC Video Surface
            VLCVideoSurface(viewModel: viewModel)
                .ignoresSafeArea()
            
            // 2. Buffering State
            // FIX: Only show the buffer overlay if buffering is true AND playback has NOT explicitly started.
            // This prevents the buffer spinner from obscuring the video during minor, transient re-buffer events once a stream is established.
            if viewModel.isBuffering && !viewModel.isPlaying {
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
    
    // MARK: - Overlays
    
    private var controlsOverlay: some View {
        ZStack {
            if viewModel.showControls || !viewModel.isPlaying {
                LinearGradient(
                    colors: [.black.opacity(0.9), .clear, .black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack {
                    // Top Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.videoTitle)
                                .font(CinemeltTheme.fontTitle(42))
                                .foregroundColor(CinemeltTheme.cream)
                            
                            if let q = channel.quality {
                                Text(q).font(CinemeltTheme.fontBody(20)).foregroundColor(CinemeltTheme.accent)
                            }
                        }
                        Spacer()
                        
                        Button(action: { viewModel.toggleFavorite() }) {
                            Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                .font(.title)
                                .foregroundColor(viewModel.isFavorite ? CinemeltTheme.accent : .white)
                                .padding(12)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(60)
                    
                    Spacer()
                    
                    // Play Button
                    if !viewModel.isPlaying && !viewModel.isBuffering {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 150))
                            .foregroundColor(CinemeltTheme.accent.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Timeline
                    VStack(spacing: 20) {
                        HStack(spacing: 30) {
                            Text(formatTime(viewModel.currentTime))
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(CinemeltTheme.accent)
                                .monospacedDigit()
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.2)).frame(height: 12)
                                    if viewModel.duration > 0 {
                                        Capsule()
                                            .fill(CinemeltTheme.accent)
                                            .frame(width: geo.size.width * (viewModel.currentTime / viewModel.duration), height: 12)
                                    }
                                }
                            }
                            .frame(height: 12)
                            
                            Text(formatTime(viewModel.duration))
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(CinemeltTheme.cream)
                                .monospacedDigit()
                        }
                        Text("Press Menu to Exit").font(CinemeltTheme.fontBody(18)).foregroundColor(.gray)
                    }
                    .padding(60)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
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
    
    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite { return "--:--" }
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
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
