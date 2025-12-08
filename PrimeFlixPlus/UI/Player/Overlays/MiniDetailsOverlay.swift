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
                
                // 1. Poster / Thumbnail (Enhanced with new metadata)
                if let poster = viewModel.posterImage {
                    AsyncImage(url: poster) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.white.opacity(0.1))
                    }
                    .frame(width: 240, height: 360) // Taller poster aspect
                    .cornerRadius(16)
                    .shadow(radius: 20)
                } else {
                    // Fallback
                    AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.white.opacity(0.1))
                    }
                    .frame(width: 240, height: 360)
                    .cornerRadius(16)
                }
                
                // 2. Info Block
                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.videoTitle.isEmpty ? channel.title : viewModel.videoTitle)
                        .font(CinemeltTheme.fontTitle(50))
                        .foregroundColor(CinemeltTheme.cream)
                        .lineLimit(2)
                        .shadow(color: .black, radius: 2)
                    
                    // Metadata Row
                    HStack(spacing: 15) {
                        Badge(text: viewModel.qualityBadge)
                        
                        if !viewModel.videoRating.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(CinemeltTheme.accent)
                                    .font(.caption)
                                Text(viewModel.videoRating)
                                    .font(CinemeltTheme.fontBody(22))
                                    .foregroundColor(CinemeltTheme.cream)
                            }
                        }
                        
                        if !viewModel.videoYear.isEmpty {
                            Text(viewModel.videoYear)
                                .font(CinemeltTheme.fontBody(22))
                                .foregroundColor(.gray)
                        }
                        
                        if let dur = viewModel.duration as Double?, dur > 0 {
                            Text("\(Int(dur / 60)) min")
                                .font(CinemeltTheme.fontBody(22))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Synopsis (Now populated from TMDB!)
                    Text(viewModel.videoOverview.isEmpty ? "No details available." : viewModel.videoOverview)
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                        .lineLimit(4)
                        .lineSpacing(4)
                    
                    // Hint
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.up")
                        Text("Swipe Up to Close")
                    }
                    .font(CinemeltTheme.fontBody(18))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 3. Actions Block
                VStack(alignment: .leading, spacing: 15) {
                    
                    Text("Controls")
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 20) {
                        if viewModel.canPlayNext {
                            Button(action: onPlayNext) {
                                HStack {
                                    Image(systemName: "forward.end.fill")
                                    VStack(alignment: .leading) {
                                        Text("Next Episode")
                                            .font(CinemeltTheme.fontTitle(24))
                                            .foregroundColor(.black)
                                        if let next = viewModel.nextEpisode {
                                            Text(next.title)
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
                        .padding(10)
                    }
                    .frame(width: 500, height: 100)
                }
                .frame(width: 500)
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
                        ).opacity(0.9)
                    )
                    .ignoresSafeArea()
            )
            .frame(height: 500)
            .cornerRadius(40, corners: [.topLeft, .topRight])
            .shadow(radius: 50)
        }
        .onExitCommand { onClose() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedButton = viewModel.canPlayNext ? "next" : "restart"
            }
        }
    }
}
