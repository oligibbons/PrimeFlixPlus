import SwiftUI

struct WatchlistView: View {
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    @StateObject private var viewModel = WatchlistViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // FOCUS MANAGEMENT
    @FocusState private var isContentFocused: Bool
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 50))
                        .foregroundColor(CinemeltTheme.accent)
                    
                    Text("Watch List")
                        .font(CinemeltTheme.fontTitle(60))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                    
                    Spacer()
                }
                .padding(.top, 20)
                // ALIGNMENT FIX: Use global margin for the header
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
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 80))
                            .foregroundColor(CinemeltTheme.accent.opacity(0.3))
                        Text("Your watch list is empty.")
                            .cinemeltBody()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 50) {
                            
                            if !viewModel.series.isEmpty {
                                WatchlistLane(title: "Series", items: viewModel.series, onPlay: onPlay)
                            }
                            
                            if !viewModel.movies.isEmpty {
                                WatchlistLane(title: "Movies", items: viewModel.movies, onPlay: onPlay)
                            }
                            
                            if !viewModel.liveChannels.isEmpty {
                                WatchlistLane(title: "Live TV", items: viewModel.liveChannels, onPlay: onPlay)
                            }
                            
                            Spacer().frame(height: 100)
                        }
                        .padding(.top, 20)
                        .focusSection()
                        .focused($isContentFocused)
                    }
                    // CRITICAL FIX: Safe padding prevents TV bezel cropping
                    .standardSafePadding()
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
        }
        .onChange(of: viewModel.isLoading) { loading in
            if !loading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isContentFocused = true
                }
            }
        }
        .onExitCommand { onBack() }
    }
}

// Reusing a similar lane structure to FavoritesLane
struct WatchlistLane: View {
    let title: String
    let items: [Channel]
    let onPlay: (Channel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
                // ALIGNMENT FIX: Align title with global margin
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
            .focusSection()
        }
    }
}
