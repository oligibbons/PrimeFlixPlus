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
        case play, favorite, version, season(Int), episode(String)
    }
    
    var body: some View {
        ZStack {
            // 1. Dynamic Background
            GeometryReader { geo in
                AsyncImage(url: viewModel.backgroundUrl ?? URL(string: viewModel.channel.cover ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.black
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(.regularMaterial) // Glass effect
                .overlay(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.6),
                            .black.opacity(0.8),
                            .black
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .ignoresSafeArea()
            
            // 2. Main Content - ScrollView handles Safe Area naturally
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    
                    // --- TOP SECTION: Metadata ---
                    HStack(alignment: .top, spacing: 50) {
                        // Poster
                        AsyncImage(url: viewModel.posterUrl ?? URL(string: viewModel.channel.cover ?? "")) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 300, height: 450)
                        .cornerRadius(12)
                        .shadow(radius: 20)
                        
                        // Info
                        VStack(alignment: .leading, spacing: 20) {
                            Text(viewModel.tmdbDetails?.title ?? viewModel.channel.title)
                                .font(.custom("Exo2-Bold", size: 60))
                                .foregroundColor(.white)
                            
                            // Stats Row
                            HStack(spacing: 20) {
                                if let rating = viewModel.tmdbDetails?.voteAverage {
                                    HStack(spacing: 5) {
                                        Image(systemName: "star.fill").foregroundColor(.yellow)
                                        Text(String(format: "%.1f", rating))
                                    }
                                }
                                
                                if let date = viewModel.tmdbDetails?.displayDate?.prefix(4) {
                                    Text(String(date))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(4)
                                }
                                
                                if let genres = viewModel.tmdbDetails?.genres {
                                    Text(genres.prefix(2).map { $0.name }.joined(separator: ", "))
                                        .foregroundColor(.cyan)
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.gray)
                            
                            // Buttons Row
                            HStack(spacing: 20) {
                                Button(action: {
                                    if viewModel.channel.type == "movie" {
                                        onPlay(viewModel.channel)
                                    } else {
                                        // Resume logic for series could go here
                                    }
                                }) {
                                    Label("Play", systemImage: "play.fill")
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                }
                                .buttonStyle(.card)
                                .focused($focusedField, equals: .play)
                                
                                Button(action: { viewModel.toggleFavorite(repository: repository) }) {
                                    Label(
                                        viewModel.isFavorite ? "Favorited" : "Favorite",
                                        systemImage: viewModel.isFavorite ? "heart.fill" : "heart"
                                    )
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.card)
                                .focused($focusedField, equals: .favorite)
                                .foregroundColor(viewModel.isFavorite ? .red : .white)
                            }
                            
                            Text(viewModel.tmdbDetails?.overview ?? "No synopsis available.")
                                .font(.body)
                                .lineSpacing(6)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(6)
                        }
                    }
                    .padding(.top, 50) // Push down slightly
                    
                    // --- SERIES SECTION ---
                    if viewModel.channel.type == "series" {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Seasons")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 20) {
                                    ForEach(viewModel.seasons, id: \.self) { season in
                                        Button(action: { viewModel.selectSeason(season) }) {
                                            Text("Season \(season)")
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.card)
                                        .focused($focusedField, equals: .season(season))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(viewModel.selectedSeason == season ? Color.cyan : Color.clear, lineWidth: 2)
                                        )
                                    }
                                }
                                .padding(.vertical, 20) // Space for focus
                            }
                            
                            Text("Episodes")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 30) {
                                    ForEach(viewModel.displayedEpisodes) { episode in
                                        Button(action: {
                                            let playable = viewModel.createPlayableChannel(for: episode)
                                            onPlay(playable)
                                        }) {
                                            EpisodeCard(episode: episode)
                                        }
                                        .buttonStyle(.card)
                                        .focused($focusedField, equals: .episode(episode.id))
                                    }
                                }
                                .padding(.vertical, 40)
                            }
                        }
                    }
                    
                    // --- CAST SECTION ---
                    if !viewModel.cast.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Cast")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 40) {
                                    ForEach(viewModel.cast) { person in
                                        CastMemberCard(person: person)
                                    }
                                }
                                .padding(.vertical, 40)
                            }
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 100)
            }
        }
        .onAppear {
            Task { await viewModel.loadData(repository: repository) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .play
            }
        }
    }
}

// MARK: - Subcomponents

struct EpisodeCard: View {
    let episode: XtreamChannelInfo.Episode
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle().fill(Color(white: 0.15))
                Image(systemName: "play.tv.fill")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
            }
            .frame(width: 300, height: 170)
            .cornerRadius(8)
            
            Text("\(episode.episodeNum). \(episode.title ?? "Episode \(episode.episodeNum)")")
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(isFocused ? .white : .gray)
                .frame(width: 300, alignment: .leading)
        }
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(), value: isFocused)
    }
}

struct CastMemberCard: View {
    let person: TmdbCast
    
    var body: some View {
        VStack {
            AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w200\(person.profilePath ?? "")")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(Color.gray.opacity(0.3))
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .shadow(radius: 5)
            
            Text(person.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(width: 120)
            
            if let char = person.character {
                Text(char)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(width: 120)
            }
        }
    }
}
