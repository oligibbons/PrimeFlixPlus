import SwiftUI

struct MiniDetailsOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    let channel: Channel
    var onPlayNext: () -> Void
    var onClose: () -> Void
    
    @FocusState private var focusedButton: String?
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(alignment: .bottom, spacing: 40) {
                
                // 1. Poster / Thumbnail
                AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.1))
                }
                .frame(width: 200, height: 300)
                .cornerRadius(12)
                .shadow(radius: 20)
                
                // 2. Info Block
                VStack(alignment: .leading, spacing: 10) {
                    Text(channel.title)
                        .font(CinemeltTheme.fontTitle(50))
                        .foregroundColor(CinemeltTheme.cream)
                        .lineLimit(2)
                    
                    // Metadata Row
                    HStack(spacing: 15) {
                        Badge(text: channel.quality ?? "HD")
                        Badge(text: channel.type.capitalized)
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
                        if let dur = viewModel.duration as Double?, dur > 0 {
                            Text("\(Int(dur / 60)) min")
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Synopsis
                    if !viewModel.videoOverview.isEmpty {
                        Text(viewModel.videoOverview)
                            .font(CinemeltTheme.fontBody(20))
                            .foregroundColor(.gray)
                            .lineLimit(3)
                    }
                    
                    // Disclaimer / Help
                    Text("Swipe Up or Press Menu to close")
                        .font(CinemeltTheme.fontBody(18))
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 3. Actions Block (Right Side)
                VStack(alignment: .leading, spacing: 15) {
                    
                    Text("Playback Controls")
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 20) {
                        // Play Next (Logic: Replaces Restart if next episode exists)
                        if viewModel.canPlayNext {
                            Button(action: onPlayNext) {
                                HStack {
                                    Image(systemName: "forward.end.fill")
                                        .font(.headline)
                                    VStack(alignment: .leading) {
                                        Text("Next Episode")
                                            .font(CinemeltTheme.fontTitle(24))
                                            .foregroundColor(.black)
                                        if let next = viewModel.nextEpisode {
                                            Text(next.title) // e.g. "S01 E02"
                                                .font(.caption)
                                                .foregroundColor(.black.opacity(0.7))
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 15)
                                .background(CinemeltTheme.accent)
                                .cornerRadius(12)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedButton, equals: "next")
                        } else {
                            // Standard Restart Button
                            Button(action: { viewModel.restartPlayback() }) {
                                VStack(spacing: 5) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.headline)
                                    Text("Restart")
                                        .font(.caption)
                                }
                                .frame(width: 100, height: 70)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedButton, equals: "restart")
                        }
                    }
                    
                    Text("Speed")
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.gray)
                        .padding(.top, 10)
                    
                    // Speed Control
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                                Button(action: { viewModel.setPlaybackSpeed(Float(speed)) }) {
                                    Text("\(String(format: "%g", speed))x")
                                        .font(CinemeltTheme.fontBody(20))
                                        .frame(width: 60, height: 40)
                                        .foregroundColor(viewModel.playbackRate == Float(speed) ? .black : .white)
                                        .background(viewModel.playbackRate == Float(speed) ? CinemeltTheme.accent : Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                                .focused($focusedButton, equals: "speed_\(speed)")
                            }
                        }
                        .padding(10) // Padding for focus expansion
                    }
                    .frame(width: 500, height: 100)
                }
                .frame(width: 600)
            }
            .padding(50)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [CinemeltTheme.charcoal, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        ).opacity(0.8)
                    )
                    .ignoresSafeArea()
            )
            .frame(height: 450) // Approx 1/3 to 1/2 screen
            .cornerRadius(40, corners: [.topLeft, .topRight])
            .shadow(radius: 50)
        }
        .onExitCommand { onClose() }
        .onAppear {
            // Default focus to next/restart button when opened
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedButton = viewModel.canPlayNext ? "next" : "restart"
            }
        }
    }
}

