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
    
    // Focus State
    @FocusState private var focusedField: FocusField?
    @Namespace private var scrollSpace
    
    enum FocusField: Hashable {
        case back, play, resume, favorite, version, season(Int), episode(String)
    }
    
    var body: some View {
        ZStack {
            // 1. Dynamic Background
            if let bgUrl = viewModel.backgroundUrl {
                AsyncImage(url: bgUrl) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.black
                }
                .ignoresSafeArea()
                .opacity(viewModel.backdropOpacity)
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.6), location: 0),
                            .init(color: .black, location: 0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(LinearGradient(colors: [.black.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 900, alignment: .leading))
            } else {
                Color.black.ignoresSafeArea()
            }
            
            // 2. Main Content
            ScrollViewReader { scrollProxy in
                ScrollView {
                    Color.clear.frame(height: 1).id("top") // Scroll anchor
                    
                    VStack(alignment: .leading, spacing: 30) {
                        
                        // --- Back Button ---
                        Button(action: onBack) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.left")
                                Text("Back")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.card)
                        .focused($focusedField, equals: .back)
                        .padding(.leading, 80)
                        .padding(.top, 40)
                        
                        // --- Header Info ---
                        VStack(alignment: .leading, spacing: 16) {
                            Text(viewModel.tmdbDetails?.displayTitle ?? viewModel.channel.title)
                                .font(.custom("Exo2-Bold", size: 68))
                                .fontWeight(.black)
                                .foregroundColor(.white)
                                .shadow(radius: 10)
                                .lineLimit(2)
                            
                            // Metadata Row
                            HStack(spacing: 12) {
                                if let v = viewModel.selectedVersion {
                                    let info = TitleNormalizer.parse(rawTitle: v.title)
                                    Text(info.quality).font(.headline).fontWeight(.bold).foregroundColor(.cyan)
                                    if let lang = info.language {
                                        Text(lang).font(.headline).foregroundColor(.gray)
                                    }
                                }
                                
                                if let score = viewModel.tmdbDetails?.voteAverage {
                                    Label(String(format: "%.1f", score), systemImage: "star.fill")
                                        .font(.headline)
                                        .foregroundColor(.black)
                                        .padding(6)
                                        .background(Color.yellow)
                                        .cornerRadius(4)
                                }
                                
                                if let year = viewModel.tmdbDetails?.displayDate?.prefix(4) {
                                    Text(String(year)).font(.headline).foregroundColor(.gray)
                                }
                            }
                            
                            Text(viewModel.tmdbDetails?.overview ?? "No synopsis available.")
                                .font(.body)
                                .lineSpacing(5)
                                .foregroundColor(.white.opacity(0.8))
                                .frame(maxWidth: 700, alignment: .leading)
                                .lineLimit(4)
                        }
                        .padding(.horizontal, 80)
                        
                        // --- Action Buttons ---
                        HStack(spacing: 20) {
                            // Play/Resume
                            Button(action: {
                                if let target = viewModel.selectedVersion {
                                    onPlay(target)
                                }
                            }) {
                                HStack {
                                    Image(systemName: viewModel.hasWatchHistory ? "clock.arrow.circlepath" : "play.fill")
                                    Text(viewModel.hasWatchHistory ? "Resume" : "Play")
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                            }
                            .buttonStyle(.card)
                            .focused($focusedField, equals: .play)
                            
                            // Version Selector
                            if viewModel.availableVersions.count > 1 && viewModel.channel.type == "movie" {
                                Button(action: { viewModel.showVersionSelector = true }) {
                                    HStack {
                                        Image(systemName: "list.bullet")
                                        Text("Versions (\(viewModel.availableVersions.count))")
                                    }
                                    .padding(12)
                                }
                                .buttonStyle(.card)
                                .focused($focusedField, equals: .version)
                            }
                            
                            // Favorite
                            Button(action: { viewModel.toggleFavorite() }) {
                                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                    .padding(12)
                            }
                            .buttonStyle(.card)
                            .focused($focusedField, equals: .favorite)
                            .foregroundColor(viewModel.isFavorite ? .red : .white)
                        }
                        .padding(.horizontal, 80)
                        
                        // --- Series Section ---
                        if viewModel.channel.type == "series" {
                            VStack(alignment: .leading) {
                                // Season Tabs
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(viewModel.seasons, id: \.self) { season in
                                            Button(action: { Task { await viewModel.selectSeason(season) } }) {
                                                Text("Season \(season)")
                                                    .fontWeight(.semibold)
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 10)
                                            }
                                            .buttonStyle(.card)
                                            .focused($focusedField, equals: .season(season))
                                            .overlay(
                                                VStack {
                                                    Spacer()
                                                    if viewModel.selectedSeason == season {
                                                        Rectangle().fill(Color.cyan).frame(height: 3)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 80)
                                }
                                
                                // Episodes Lane
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
                                    .padding(.horizontal, 80)
                                    .padding(.vertical, 30)
                                }
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
                // Menu button handler
                .onExitCommand {
                    if focusedField == .play || focusedField == .back || focusedField == .resume {
                        onBack()
                    } else {
                        withAnimation {
                            scrollProxy.scrollTo("top", anchor: .top)
                            focusedField = .play
                        }
                    }
                }
            }
            
            // 3. Version Selector Modal
            if viewModel.showVersionSelector {
                Color.black.opacity(0.8).ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Select Version").font(.title3).fontWeight(.bold).foregroundColor(.white)
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(viewModel.availableVersions, id: \.url) { v in
                                Button(action: { viewModel.userSelectedVersion(v) }) {
                                    HStack {
                                        Text(v.title).lineLimit(1)
                                        Spacer()
                                        if viewModel.selectedVersion == v {
                                            Image(systemName: "checkmark").foregroundColor(.cyan)
                                        }
                                    }
                                    .padding()
                                    .frame(width: 500)
                                }
                                .buttonStyle(.card)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 400)
                    Button("Cancel") { viewModel.showVersionSelector = false }
                        .buttonStyle(.plain).padding()
                }
                .padding(40)
                .background(Color(white: 0.15))
                .cornerRadius(24)
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
            Task { await viewModel.loadData() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .play
            }
        }
    }
}

// MARK: - Subviews

struct EpisodeCard: View {
    let episode: DetailsViewModel.MergedEpisode
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: episode.imageUrl) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color(white: 0.15)
                        Image(systemName: "tv").font(.largeTitle).foregroundColor(.gray)
                    }
                }
                .frame(width: 320, height: 180)
                .clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .center))
                
                Text("\(episode.number). \(episode.title)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(10)
                    .lineLimit(1)
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? Color.cyan : Color.clear, lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.spring(), value: isFocused)
            
            if isFocused {
                Text(episode.overview)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(3)
                    .frame(width: 320, alignment: .leading)
            }
        }
        .focused($isFocused)
    }
}
