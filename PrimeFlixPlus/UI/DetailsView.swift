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
            // 1. Hero Background with Cinematic Fade
            GeometryReader { geo in
                if let bgUrl = viewModel.backgroundUrl {
                    AsyncImage(url: bgUrl) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height + 100)
                            .clipped()
                    } placeholder: {
                        CinemeltTheme.backgroundEnd
                    }
                } else {
                    CinemeltTheme.backgroundEnd
                }
            }
            .ignoresSafeArea()
            
            // 2. Gradients for readability
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: CinemeltTheme.backgroundStart.opacity(0.6), location: 0.4),
                    .init(color: CinemeltTheme.backgroundStart, location: 0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            HStack {
                LinearGradient(colors: [CinemeltTheme.backgroundStart.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 900)
                Spacer()
            }
            .ignoresSafeArea()
            
            // 3. Content
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    
                    Spacer().frame(height: 380) // Push content down
                    
                    // --- Title & Metadata ---
                    VStack(alignment: .leading, spacing: 15) {
                        Text(viewModel.tmdbDetails?.displayTitle ?? viewModel.channel.title)
                            .font(CinemeltTheme.fontTitle(70))
                            .foregroundColor(CinemeltTheme.cream)
                            .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 5)
                            .lineLimit(2)
                        
                        HStack(spacing: 20) {
                            // Quality Badge
                            if let v = viewModel.selectedVersion {
                                let info = TitleNormalizer.parse(rawTitle: v.title)
                                Text(info.quality)
                                    .font(CinemeltTheme.fontTitle(18))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(CinemeltTheme.accent)
                                    .cornerRadius(6)
                            }
                            
                            // Rating
                            if let score = viewModel.tmdbDetails?.voteAverage {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill").foregroundColor(CinemeltTheme.accent)
                                    Text(String(format: "%.1f", score))
                                        .font(CinemeltTheme.fontBody(20))
                                        .foregroundColor(CinemeltTheme.cream)
                                }
                            }
                            
                            // Year
                            if let year = viewModel.tmdbDetails?.displayDate?.prefix(4) {
                                Text(String(year))
                                    .font(CinemeltTheme.fontBody(20))
                                    .foregroundColor(.gray)
                            }
                            
                            // Runtime
                            if let runtime = viewModel.tmdbDetails?.runtime, runtime > 0 {
                                Text(formatRuntime(runtime))
                                    .font(CinemeltTheme.fontBody(20))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Text(viewModel.tmdbDetails?.overview ?? "No synopsis available.")
                            .font(CinemeltTheme.fontBody(24))
                            .lineSpacing(6)
                            .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                            .frame(maxWidth: 800, alignment: .leading)
                            .lineLimit(4)
                    }
                    .padding(.horizontal, 60)
                    
                    // --- Actions ---
                    HStack(spacing: 20) {
                        Button(action: {
                            if let playable = viewModel.getSmartPlayTarget() { onPlay(playable) }
                        }) {
                            HStack {
                                Image(systemName: viewModel.hasWatchHistory ? "play.circle.fill" : "play.fill")
                                Text(viewModel.hasWatchHistory ? "Resume" : "Play")
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.card)
                        .focused($focusedField, equals: .play)
                        
                        // Trailer
                        if let videos = viewModel.tmdbDetails?.videos?.results, !videos.filter({ $0.type == "Trailer" }).isEmpty {
                            Button(action: { print("Play Trailer logic") }) {
                                HStack {
                                    Image(systemName: "video.fill")
                                    Text("Trailer")
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.card)
                            .focused($focusedField, equals: .trailer)
                        }
                        
                        // Favorite
                        Button(action: { viewModel.toggleFavorite() }) {
                            Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                .padding(12)
                        }
                        .buttonStyle(.card)
                        .focused($focusedField, equals: .favorite)
                        .foregroundColor(viewModel.isFavorite ? CinemeltTheme.accent : .white)
                    }
                    .padding(.horizontal, 60)
                    
                    // --- Cast Rail ---
                    if !viewModel.cast.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Cast")
                                .font(CinemeltTheme.fontTitle(28))
                                .foregroundColor(CinemeltTheme.cream)
                                .padding(.leading, 60)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 30) {
                                    ForEach(viewModel.cast) { actor in
                                        VStack {
                                            AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w200\(actor.profilePath ?? "")")) { img in
                                                img.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Circle().fill(Color.white.opacity(0.1))
                                            }
                                            .frame(width: 100, height: 100)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                                            
                                            Text(actor.name)
                                                .font(CinemeltTheme.fontBody(18))
                                                .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                                                .lineLimit(1)
                                                .frame(width: 120)
                                        }
                                    }
                                }
                                .padding(.horizontal, 60)
                                .padding(.bottom, 20)
                            }
                        }
                    }
                    
                    // --- Episodes (Series Only) ---
                    if viewModel.channel.type == "series" {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Seasons")
                                .font(CinemeltTheme.fontTitle(28))
                                .foregroundColor(CinemeltTheme.cream)
                                .padding(.leading, 60)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    ForEach(viewModel.seasons, id: \.self) { season in
                                        Button(action: { Task { await viewModel.selectSeason(season) } }) {
                                            Text("Season \(season)")
                                                .font(CinemeltTheme.fontBody(22))
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.card)
                                        .focused($focusedField, equals: .season(season))
                                        .overlay(
                                            VStack {
                                                Spacer()
                                                if viewModel.selectedSeason == season {
                                                    Rectangle().fill(CinemeltTheme.accent).frame(height: 3)
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 60)
                                .padding(.vertical, 20) // Focus expansion space
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 40) {
                                    ForEach(viewModel.displayedEpisodes) { ep in
                                        Button(action: { onPlay(viewModel.createPlayableChannel(for: ep)) }) {
                                            EpisodeCard(episode: ep)
                                        }
                                        .buttonStyle(.card)
                                        .focused($focusedField, equals: .episode(ep.id))
                                    }
                                }
                                .padding(.horizontal, 60)
                                .padding(.vertical, 40)
                            }
                        }
                    }
                    
                    Spacer(minLength: 150)
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
            Task { await viewModel.loadData() }
        }
        .onExitCommand { onBack() }
    }
    
    private func formatRuntime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
