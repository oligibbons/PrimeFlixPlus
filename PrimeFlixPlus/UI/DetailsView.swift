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
    
    // Navigation State
    @FocusState private var focusedField: FocusField?
    @Namespace private var scrollSpace // For scroll-to-top logic
    
    enum FocusField: Hashable {
        case back, play, resume, favorite, version, season(Int), episode(String)
    }
    
    var body: some View {
        ZStack {
            // 1. Background
            if let bgUrl = viewModel.backgroundUrl {
                AsyncImage(url: bgUrl) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.black }
                .ignoresSafeArea()
                .opacity(viewModel.backdropOpacity)
                .overlay(
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.6), location: 0),
                        .init(color: .black, location: 0.8)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .overlay(LinearGradient(colors: [.black.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 900, alignment: .leading))
            } else {
                Color.black.ignoresSafeArea()
            }
            
            // 2. Main Scrollable Content
            ScrollViewReader { scrollProxy in
                ScrollView {
                    // Anchor for scrolling to top
                    Color.clear.frame(height: 1).id("top")
                    
                    VStack(alignment: .leading, spacing: 30) {
                        
                        // --- BACK BUTTON ---
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
                        
                        // --- HEADER INFO ---
                        VStack(alignment: .leading, spacing: 16) {
                            // Title
                            Text(viewModel.tmdbDetails?.displayTitle ?? viewModel.channel.title)
                                .font(.custom("Exo2-Bold", size: 68))
                                .fontWeight(.black)
                                .foregroundColor(.white)
                                .shadow(radius: 10)
                                .lineLimit(2)
                            
                            // Metadata Badges
                            HStack(spacing: 12) {
                                // Dynamic Resolution Badge (from current selection)
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
                            
                            // Overview
                            Text(viewModel.tmdbDetails?.overview ?? "")
                                .font(.body)
                                .lineSpacing(5)
                                .foregroundColor(.white.opacity(0.8))
                                .frame(maxWidth: 700, alignment: .leading)
                                .lineLimit(4)
                        }
                        .padding(.horizontal, 80)
                        
                        // --- ACTIONS ---
                        HStack(spacing: 20) {
                            // 1. Play/Resume
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
                            
                            // 2. Versions (If duplicates exist)
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
                            
                            // 3. Favorite
                            Button(action: { viewModel.toggleFavorite() }) {
                                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                    .padding(12)
                            }
                            .buttonStyle(.card)
                            .focused($focusedField, equals: .favorite)
                            .foregroundColor(viewModel.isFavorite ? .red : .white)
                        }
                        .padding(.horizontal, 80)
                        
                        // --- SERIES SEASONS ---
                        if viewModel.channel.type == "series" {
                            VStack(alignment: .leading) {
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
                                
                                // Episodes
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
                // --- MENU BUTTON INTERCEPTION ---
                .onExitCommand {
                    // Logic: If focused on Play button or Back button, go Back.
                    // Otherwise, scroll to top first.
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
                        .buttonStyle(.plain)
                        .padding()
                }
                .padding(40)
                .background(Color(white: 0.15))
                .cornerRadius(24)
                .transition(.opacity)
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
            Task { await viewModel.loadData() }
            // Initial Focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .play
            }
        }
    }
}
