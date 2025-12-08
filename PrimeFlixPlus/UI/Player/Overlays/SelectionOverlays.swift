import SwiftUI

// MARK: - Version Selection Overlay
struct VersionSelectionOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    var onClose: () -> Void
    @FocusState private var focusedVersion: String?
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Select Version")
                    .font(CinemeltTheme.fontTitle(40))
                    .foregroundColor(CinemeltTheme.cream)
                    .cinemeltGlow()
                
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(viewModel.alternativeVersions, id: \.url) { channel in
                            Button(action: { viewModel.switchVersion(channel) }) {
                                HStack {
                                    Text(channel.quality ?? "Unknown Quality")
                                        .font(CinemeltTheme.fontTitle(24))
                                        .foregroundColor(.white)
                                    Spacer()
                                    if channel.url == viewModel.currentUrl {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(CinemeltTheme.accent)
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedVersion, equals: channel.url)
                        }
                    }
                    .padding(40)
                }
                .frame(width: 500, height: 600)
            }
        }
        .onExitCommand { onClose() }
    }
}

// MARK: - Track Selection Overlay
struct TrackSelectionOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    var onClose: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            HStack(alignment: .top, spacing: 100) {
                
                // Audio Column
                trackColumn(title: "Audio", tracks: viewModel.audioTracks, currentIndex: viewModel.currentAudioIndex) { i in
                    viewModel.setAudioTrack(index: i)
                }
                
                // Subtitle Column
                trackColumn(title: "Subtitles", tracks: viewModel.subtitleTracks, currentIndex: viewModel.currentSubtitleIndex) { i in
                    viewModel.setSubtitleTrack(index: i)
                }
                
            }
            .frame(height: 600)
        }
        // Menu button to close overlay
        .onExitCommand {
            onClose()
        }
    }
    
    private func trackColumn(title: String, tracks: [String], currentIndex: Int, action: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.accent)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if tracks.isEmpty {
                        Text("No tracks found")
                            .font(CinemeltTheme.fontBody(20))
                            .foregroundColor(.gray)
                    } else {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                            Button(action: { action(index) }) {
                                HStack {
                                    Text(track)
                                        .font(CinemeltTheme.fontBody(22))
                                        .foregroundColor(.white)
                                    Spacer()
                                    if index == currentIndex {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(CinemeltTheme.accent)
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                        }
                    }
                }
            }
        }
        .frame(width: 400)
    }
}

// MARK: - Auto Play Overlay
struct AutoPlayOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    @FocusState private var isPlayNowFocused: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            HStack(spacing: 60) {
                // Info
                VStack(alignment: .leading, spacing: 20) {
                    Text("Up Next")
                        .font(CinemeltTheme.fontBody(28))
                        .foregroundColor(.gray)
                    
                    if let next = viewModel.nextEpisode {
                        Text(next.title)
                            .font(CinemeltTheme.fontTitle(50))
                            .foregroundColor(CinemeltTheme.cream)
                            .lineLimit(2)
                            .cinemeltGlow()
                    }
                    
                    HStack(spacing: 15) {
                        Image(systemName: "timer")
                            .foregroundColor(CinemeltTheme.accent)
                        Text("Playing in \(viewModel.autoPlayCounter) seconds")
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(CinemeltTheme.accent)
                            .monospacedDigit()
                    }
                }
                .frame(width: 500)
                
                // Actions
                VStack(spacing: 20) {
                    Button(action: { viewModel.confirmAutoPlay() }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play Now")
                        }
                        .font(CinemeltTheme.fontTitle(28))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 20)
                        .background(CinemeltTheme.accent)
                        .cornerRadius(16)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                    .focused($isPlayNowFocused)
                    
                    Button(action: { viewModel.cancelAutoPlay() }) {
                        Text("Cancel")
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                }
            }
        }
        .onAppear {
            isPlayNowFocused = true
        }
    }
}

