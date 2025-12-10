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
                .padding(.top, 20)
                // ALIGNMENT FIX: Use global margin
                .padding(.horizontal, CinemeltTheme.Layout.margin)
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
                    // CRITICAL FIX: Safe Padding
                    .standardSafePadding()
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
        }
        .onExitCommand { onBack() }
    }
}

// Lane structure
struct FavoritesLane: View {
    let title: String
    let items: [Channel]
    let onPlay: (Channel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
                // ALIGNMENT FIX
                .padding(.leading, CinemeltTheme.Layout.margin)
                .cinemeltGlow()
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 60) {
                    ForEach(items) { channel in
                        MovieCard(channel: channel) {
                            onPlay(channel)
                        }
                    }
                }
                // Padding for focus expansion & alignment
                .padding(.horizontal, CinemeltTheme.Layout.margin)
                .padding(.vertical, 60)
            }
        }
    }
}
