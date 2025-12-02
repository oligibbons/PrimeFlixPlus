import SwiftUI

struct DetailsView: View {
    @StateObject private var viewModel: DetailsViewModel
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    init(channel: Channel, onPlay: @escaping (Channel) -> Void, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: DetailsViewModel(channel: channel))
        self.onPlay = onPlay
        self.onBack = onBack
    }
    
    @FocusState private var focusedElement: String?
    
    var body: some View {
        ZStack {
            // 1. Dynamic Background
            AsyncImage(url: viewModel.backgroundUrl ?? URL(string: viewModel.channel.cover ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.black
            }
            .ignoresSafeArea()
            .overlay(.regularMaterial) // Blur effect
            .overlay(LinearGradient(colors: [.black.opacity(0.3), .black], startPoint: .top, endPoint: .bottom))
            
            HStack(alignment: .top, spacing: 50) {
                
                // 2. Left Pane: Poster & Info
                VStack(alignment: .leading, spacing: 20) {
                    AsyncImage(url: viewModel.posterUrl ?? URL(string: viewModel.channel.cover ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 350, height: 525)
                    .cornerRadius(16)
                    .shadow(radius: 20)
                    
                    // Action Buttons
                    HStack(spacing: 20) {
                        if viewModel.channel.type == "movie" {
                            Button(action: { onPlay(viewModel.channel) }) {
                                Label("Play Movie", systemImage: "play.fill")
                                    .font(.headline)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.card)
                            .focused($focusedElement, equals: "playButton")
                        } else {
                            // Series Info
                            VStack(alignment: .leading) {
                                Text("\(viewModel.seasons.count) Seasons")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .frame(width: 350)
                    
                    Button("Back", action: onBack)
                        .padding(.top, 20)
                }
                
                // 3. Right Pane: Details & Episodes
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(viewModel.tmdbDetails?.title ?? viewModel.channel.title)
                            .font(.system(size: 60, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        // Metadata Row
                        HStack(spacing: 15) {
                            if let rating = viewModel.tmdbDetails?.voteAverage {
                                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                    .foregroundColor(.yellow)
                            }
                            if let date = viewModel.tmdbDetails?.releaseDate?.prefix(4) {
                                Text(String(date)).foregroundColor(.gray)
                            }
                            if let genres = viewModel.tmdbDetails?.genres {
                                Text(genres.prefix(3).map { $0.name }.joined(separator: ", "))
                                    .foregroundColor(.cyan)
                            }
                        }
                        .font(.headline)
                        
                        Text(viewModel.tmdbDetails?.overview ?? "No description available.")
                            .font(.body)
                            .lineSpacing(4)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(6)
                        
                        Divider().background(Color.gray)
                        
                        // 4. Series Logic: Episodes
                        if viewModel.channel.type == "series" {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Episodes")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.cyan)
                                
                                // Season Selector
                                ScrollView(.horizontal) {
                                    HStack {
                                        ForEach(viewModel.seasons, id: \.self) { season in
                                            Button("Season \(season)") {
                                                viewModel.selectSeason(season)
                                            }
                                            .buttonStyle(.card)
                                            .foregroundColor(viewModel.selectedSeason == season ? .cyan : .white)
                                        }
                                    }
                                    .padding(.bottom, 10)
                                }
                                
                                // Episode List
                                LazyVStack(spacing: 10) {
                                    ForEach(viewModel.displayedEpisodes) { episode in
                                        Button(action: {
                                            let playable = viewModel.createPlayableChannel(for: episode)
                                            onPlay(playable)
                                        }) {
                                            HStack {
                                                Text("\(episode.episodeNum).")
                                                    .font(.headline)
                                                    .foregroundColor(.gray)
                                                    .frame(width: 40)
                                                
                                                Text(episode.title ?? "Episode \(episode.episodeNum)")
                                                    .fontWeight(.semibold)
                                                
                                                Spacer()
                                                
                                                Image(systemName: "play.circle")
                                                    .foregroundColor(.white.opacity(0.5))
                                            }
                                            .padding()
                                            .background(Color(white: 0.15))
                                            .cornerRadius(10)
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                            }
                        }
                        
                        // Cast List
                        if !viewModel.cast.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Cast")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 30) {
                                        ForEach(viewModel.cast) { castMember in
                                            VStack {
                                                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w200\(castMember.profilePath ?? "")")) { img in
                                                    img.resizable().aspectRatio(contentMode: .fill)
                                                } placeholder: {
                                                    Circle().fill(Color.gray.opacity(0.3))
                                                }
                                                .frame(width: 80, height: 80)
                                                .clipShape(Circle())
                                                
                                                Text(castMember.name)
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .frame(width: 80)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 20)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 50)
                    .padding(.bottom, 50)
                }
            }
            .padding(50)
        }
        .background(Color.black)
        .onAppear {
            Task { await viewModel.loadData() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedElement = "playButton"
            }
        }
    }
}
