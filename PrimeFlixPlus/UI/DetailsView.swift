import SwiftUI

struct DetailsView: View {
    @StateObject private var viewModel: DetailsViewModel
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    init(channel: Channel, onPlay: @escaping (Channel) -> Void, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: DetailsViewModel(channel: channel))
        self.onPlay = onPlay
        self.onBack = onBack
    }
    
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case play, trailer, favorite, season(Int), episode(String)
    }
    
    var body: some View {
        ZStack {
            // 0. Base
            CinemeltTheme.charcoal.ignoresSafeArea()
            
            // 1. Background (Optimized)
            backgroundLayer
            
            // 2. Content
            if viewModel.isLoading {
                loadingState
            } else {
                contentScrollView
            }
        }
        .onAppear {
            // Configure repository first
            viewModel.configure(repository: repository)
        }
        .task {
            // Use .task for async data loading to not block the transition
            await viewModel.loadData()
            // Default focus to Play button after load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .play
            }
        }
        .onExitCommand { onBack() }
    }
    
    // MARK: - Subviews
    
    private var backgroundLayer: some View {
        GeometryReader { geo in
            if let bgUrl = viewModel.backgroundUrl {
                AsyncImage(url: bgUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height + 100)
                            .overlay(
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black.opacity(0.8), location: 0.4),
                                        .init(color: .clear, location: 0.9)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .opacity(viewModel.backdropOpacity)
                    case .empty, .failure:
                        CinemeltTheme.mainBackground
                    @unknown default:
                        CinemeltTheme.mainBackground
                    }
                }
            } else {
                CinemeltTheme.mainBackground
            }
        }
        .ignoresSafeArea()
        .overlay(
            // Horizontal Gradient Scrim
            HStack {
                LinearGradient(
                    colors: [
                        CinemeltTheme.charcoal,
                        CinemeltTheme.charcoal.opacity(0.9),
                        CinemeltTheme.charcoal.opacity(0.4),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 1200)
                Spacer()
            }
            .ignoresSafeArea()
        )
    }
    
    private var loadingState: some View {
        VStack(spacing: 30) {
            ProgressView()
                .tint(CinemeltTheme.accent)
                .scaleEffect(2.5)
            
            Text("Loading Details...")
                .font(CinemeltTheme.fontBody(28))
                .foregroundColor(CinemeltTheme.cream.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial) // Glass effect
        .transition(.opacity)
    }
    
    private var contentScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                
                Spacer().frame(height: 350)
                
                // --- Title & Metadata ---
                VStack(alignment: .leading, spacing: 15) {
                    Text(viewModel.tmdbDetails?.displayTitle ?? viewModel.channel.title)
                        .font(CinemeltTheme.fontTitle(90))
                        .foregroundColor(CinemeltTheme.cream)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 5)
                    
                    metadataRow
                    
                    Text(viewModel.tmdbDetails?.overview ?? "No synopsis available.")
                        .font(CinemeltTheme.fontBody(28))
                        .lineSpacing(8)
                        .foregroundColor(CinemeltTheme.cream.opacity(0.9))
                        .frame(maxWidth: 950, alignment: .leading)
                        .lineLimit(4)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 80)
                
                // --- Buttons ---
                actionButtons
                    .padding(.horizontal, 80)
                
                // --- Cast ---
                if !viewModel.cast.isEmpty {
                    castRail
                }
                
                // --- Seasons/Episodes (Series Only) ---
                if viewModel.channel.type == "series" {
                    seriesContent
                }
                
                Spacer(minLength: 150)
            }
        }
        .transition(.opacity)
    }
    
    private var metadataRow: some View {
        HStack(spacing: 25) {
            if let v = viewModel.selectedVersion {
                // Use stored quality if available to avoid re-parsing
                Text(v.quality ?? "HD")
                    .font(CinemeltTheme.fontTitle(20))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(CinemeltTheme.accent)
                    .cornerRadius(8)
            }
            
            if let score = viewModel.tmdbDetails?.voteAverage {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundColor(CinemeltTheme.accent)
                    Text(String(format: "%.1f", score))
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(CinemeltTheme.cream)
                }
            }
            
            if let year = viewModel.tmdbDetails?.displayDate?.prefix(4) {
                Text(String(year))
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(.gray)
            }
            
            if let runtime = viewModel.tmdbDetails?.runtime, runtime > 0 {
                Text(formatRuntime(runtime))
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 30) {
            Button(action: {
                if let playable = viewModel.getSmartPlayTarget() { onPlay(playable) }
            }) {
                HStack(spacing: 15) {
                    Image(systemName: viewModel.hasWatchHistory ? "play.circle.fill" : "play.fill")
                    Text(viewModel.hasWatchHistory ? "Resume" : "Play Now")
                }
                .font(CinemeltTheme.fontTitle(28))
                .foregroundColor(.black)
                .padding(.horizontal, 40)
                .padding(.vertical, 18)
                .background(CinemeltTheme.accent)
                .cornerRadius(16)
            }
            .buttonStyle(CinemeltCardButtonStyle())
            .focused($focusedField, equals: .play)
            
            // Trailer Button (Only if available)
            if let videos = viewModel.tmdbDetails?.videos?.results, !videos.filter({ $0.type == "Trailer" }).isEmpty {
                Button(action: { /* Trailer logic */ }) {
                    HStack {
                        Image(systemName: "video.fill")
                        Text("Trailer")
                    }
                    .font(CinemeltTheme.fontTitle(28))
                    .foregroundColor(CinemeltTheme.cream)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 18)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(16)
                }
                .buttonStyle(CinemeltCardButtonStyle())
                .focused($focusedField, equals: .trailer)
            }
            
            // Favorite Button
            Button(action: { viewModel.toggleFavorite() }) {
                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 30))
                    .foregroundColor(viewModel.isFavorite ? CinemeltTheme.accent : .white)
                    .padding(22)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(CinemeltCardButtonStyle())
            .focused($focusedField, equals: .favorite)
        }
    }
    
    private var castRail: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cast")
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
                .padding(.leading, 80)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(viewModel.cast) { actor in
                        VStack(spacing: 15) {
                            AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w200\(actor.profilePath ?? "")")) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle().fill(Color.white.opacity(0.1))
                            }
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                            .shadow(radius: 5)
                            
                            Text(actor.name)
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                                .lineLimit(1)
                                .frame(width: 140)
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 20)
            }
        }
    }
    
    private var seriesContent: some View {
        VStack(alignment: .leading, spacing: 25) {
            // Season Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(viewModel.seasons, id: \.self) { season in
                        Button(action: { Task { await viewModel.selectSeason(season) } }) {
                            Text("Season \(season)")
                                .font(CinemeltTheme.fontTitle(22))
                                .foregroundColor(viewModel.selectedSeason == season ? .black : CinemeltTheme.cream)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(
                                    viewModel.selectedSeason == season ?
                                    CinemeltTheme.accent : Color.white.opacity(0.05)
                                )
                                .cornerRadius(30)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedField, equals: .season(season))
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
            
            // Episodes List
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 50) {
                    ForEach(viewModel.displayedEpisodes) { ep in
                        Button(action: { onPlay(viewModel.createPlayableChannel(for: ep)) }) {
                            EpisodeCard(episode: ep)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedField, equals: .episode(ep.id))
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
        }
    }
    
    private func formatRuntime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
