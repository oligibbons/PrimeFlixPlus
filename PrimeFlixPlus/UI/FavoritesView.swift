import SwiftUI

struct FavoritesView: View {
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    @StateObject private var viewModel = FavoritesViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 50))
                        .foregroundColor(CinemeltTheme.accent)
                    
                    Text("My List")
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
                        Image(systemName: "heart.slash")
                            .font(.system(size: 80))
                            .foregroundColor(CinemeltTheme.accent.opacity(0.3))
                        Text("No favorites yet.")
                            .cinemeltBody()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 50) {
                            
                            if !viewModel.series.isEmpty {
                                FavoritesLane(title: "Series", items: viewModel.series, onPlay: onPlay)
                            }
                            
                            if !viewModel.movies.isEmpty {
                                FavoritesLane(title: "Movies", items: viewModel.movies, onPlay: onPlay)
                            }
                            
                            if !viewModel.liveChannels.isEmpty {
                                FavoritesLane(title: "Live TV", items: viewModel.liveChannels, onPlay: onPlay)
                            }
                            
                            Spacer().frame(height: 100)
                        }
                        .padding(.top, 20)
                        .focusSection()
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

// Reusing a similar lane structure to ContinueWatching but with standard MovieCards
struct FavoritesLane: View {
    let title: String
    let items: [Channel]
    let onPlay: (Channel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
                .padding(.leading, 60)
                .cinemeltGlow()
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 60) {
                    ForEach(items) { channel in
                        MovieCard(channel: channel) {
                            onPlay(channel)
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 60) // Padding for focus zoom
            }
        }
    }
}
