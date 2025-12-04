import SwiftUI

struct ContinueWatchingView: View {
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    @StateObject private var viewModel = ContinueWatchingViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 50))
                        .foregroundColor(CinemeltTheme.accent)
                    
                    Text("Continue Watching")
                        .font(CinemeltTheme.fontTitle(60))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                    
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.horizontal, 80)
                .padding(.bottom, 20)
                
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView().tint(CinemeltTheme.accent).scaleEffect(2.0)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if viewModel.movies.isEmpty && viewModel.series.isEmpty && viewModel.liveChannels.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "deskclock")
                            .font(.system(size: 80))
                            .foregroundColor(CinemeltTheme.accent.opacity(0.3))
                        Text("No history yet.")
                            .cinemeltBody()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 50) {
                            
                            if !viewModel.series.isEmpty {
                                ContinueWatchingLane(title: "Series", items: viewModel.series, onItemClick: onPlay)
                            }
                            
                            if !viewModel.movies.isEmpty {
                                ContinueWatchingLane(title: "Movies", items: viewModel.movies, onItemClick: onPlay)
                            }
                            
                            if !viewModel.liveChannels.isEmpty {
                                ContinueWatchingLane(title: "Live TV (Last 10)", items: viewModel.liveChannels, onItemClick: onPlay)
                            }
                            
                            Spacer().frame(height: 100)
                        }
                        .padding(.top, 20)
                        .focusSection() // Ensure navigation flows correctly inside the scroll
                    }
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
        }
        .onExitCommand { onBack() }
    }
}
