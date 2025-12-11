import SwiftUI

struct FavoritesView: View {
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    @StateObject private var viewModel = FavoritesViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // Focus Management
    @FocusState private var focusedField: FavoritesFocus?
    
    enum FavoritesFocus: Hashable {
        case content // The grid/list
    }
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground
                .ignoresSafeArea()
            
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
                // Match global margins
                .padding(.horizontal, CinemeltTheme.Layout.margin)
                .padding(.bottom, 20)
                
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        CinemeltLoadingIndicator()
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
                            
                            // 1. Series
                            if !viewModel.series.isEmpty {
                                FavoritesLane(
                                    title: "Series",
                                    items: viewModel.series,
                                    onPlay: onPlay
                                )
                            }
                            
                            // 2. Movies
                            if !viewModel.movies.isEmpty {
                                FavoritesLane(
                                    title: "Movies",
                                    items: viewModel.movies,
                                    onPlay: onPlay
                                )
                            }
                            
                            // 3. Live TV
                            if !viewModel.liveChannels.isEmpty {
                                FavoritesLane(
                                    title: "Live TV",
                                    items: viewModel.liveChannels,
                                    onPlay: onPlay
                                )
                            }
                            
                            Spacer().frame(height: 100)
                        }
                        .padding(.top, 20)
                        
                        // Assign the focus tag to the whole content block
                        // This allows the "onAppear" force-focus to land somewhere valid
                        .focused($focusedField, equals: .content)
                    }
                    // CRITICAL: Standard Safe Padding
                    .standardSafePadding()
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
            
            // FORCE FOCUS to content, bypassing sidebar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if focusedField == nil {
                    focusedField = .content
                }
            }
        }
        .onExitCommand { onBack() }
    }
}

// Helper Subview
struct FavoritesLane: View {
    let title: String
    let items: [Channel]
    let onPlay: (Channel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
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
                // Focus bloom padding
                .padding(.horizontal, CinemeltTheme.Layout.margin)
                .padding(.vertical, 60)
            }
            .focusSection()
        }
    }
}
