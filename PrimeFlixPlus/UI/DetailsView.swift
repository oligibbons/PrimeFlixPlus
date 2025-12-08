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
        case play, favorite, version, season(Int), episode(String), cast, similar
    }
    
    var body: some View {
        ZStack {
            // 0. Base
            CinemeltTheme.charcoal.ignoresSafeArea()
            
            // 1. Background (GPU Optimized)
            backgroundLayer
                .drawingGroup()
            
            // 2. Content
            if viewModel.isLoading {
                loadingState
            } else {
                contentScrollView
                    .transition(.opacity.animation(.easeIn(duration: 0.3)))
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
        }
        .task {
            await viewModel.loadData()
            
            // Initial focus behavior
            if focusedField == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .play
                }
            }
        }
        .onExitCommand { onBack() }
        
        // --- SHEET 1: Episode Version Picker ---
        // Displayed when an episode has multiple versions (e.g. 4K, 1080p, French)
        .confirmationDialog(
            "Select Version",
            isPresented: $viewModel.showEpisodeVersionPicker,
            titleVisibility: .visible
        ) {
            if let ep = viewModel.episodeToPlay {
                ForEach(ep.versions) { v in
                    Button(v.qualityLabel.isEmpty ? "Default" : v.qualityLabel) {
                        onPlay(viewModel.getPlayableChannel(version: v, metadata: ep))
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        
        // --- SHEET 2: Top-Level Version Selector ---
        // Displayed when the Movie (or Series Container) has multiple versions
        .confirmationDialog(
            "Select Quality",
            isPresented: $viewModel.showVersionSelector,
            titleVisibility: .visible
        ) {
            ForEach(viewModel.availableVersions) { option in
                Button(option.label) {
                    viewModel.userSelectedVersion(option.channel)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
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
                                        .init(color: .black.opacity(0.6), location: 0.4),
                                        .init(color: CinemeltTheme.charcoal, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .opacity(viewModel.backdropOpacity)
                    default:
                        CinemeltTheme.mainBackground
                    }
                }
            } else {
                CinemeltTheme.mainBackground
            }
        }
        .ignoresSafeArea()
    }
    
    private var loadingState: some View {
        VStack(spacing: 30) {
            CinemeltLoadingIndicator()
            
            Text("Loading Details...")
                .font(CinemeltTheme.fontBody(24))
                .foregroundColor(CinemeltTheme.cream.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
    
    private var contentScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                
                Spacer().frame(height: 350)
                
                // --- Title & Metadata ---
                VStack(alignment: .leading, spacing: 15) {
                    // Logo or Title
                    // Priority: OMDB (Series) -> TMDB (Movies) -> Local
                    Text(viewModel.omdbDetails?.title ?? viewModel.tmdbDetails?.displayTitle ?? viewModel.channel.title)
                        .font(CinemeltTheme.fontTitle(90))
                        .foregroundColor(CinemeltTheme.cream)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 5)
                    
                    metadataRow
                    
                    // Plot
                    Text(viewModel.omdbDetails?.plot ?? viewModel.tmdbDetails?.overview ?? "No synopsis available.")
                        .font(CinemeltTheme.fontBody(28))
                        .lineSpacing(8)
                        .foregroundColor(CinemeltTheme.cream.opacity(0.9))
                        .frame(maxWidth: 950, alignment: .leading)
                        .lineLimit(4)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 80)
                .focusSection()
                
                // --- Buttons ---
                actionButtons
                    .padding(.horizontal, 80)
                    .focusSection()
                
                // --- Top-Level Version Selector (If multiple versions found) ---
                if viewModel.availableVersions.count > 1 {
                    versionSelectorButton
                        .padding(.horizontal, 80)
                        .focusSection()
                }
                
                // --- Cast Rail ---
                if !viewModel.cast.isEmpty {
                    castRail
                        .focusSection()
                }
                
                // --- Similar Content Rail ---
                if !viewModel.similarContent.isEmpty {
                    similarContentRail
                        .focusSection()
                }
                
                // --- Seasons/Episodes (Series Only) ---
                if viewModel.channel.type == "series" || viewModel.channel.type == "series_episode" {
                    seriesContent
                }
                
                Spacer(minLength: 150)
            }
        }
    }
    
    private var metadataRow: some View {
        HStack(spacing: 25) {
            // Quality Badge (Derived from selected version)
            if let v = viewModel.selectedVersion {
                Text(v.quality ?? "HD")
                    .font(CinemeltTheme.fontTitle(20))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(CinemeltTheme.accent)
                    .cornerRadius(8)
            }
            
            // NEW: OMDB Ratings Display
            if !viewModel.externalRatings.isEmpty {
                ForEach(viewModel.externalRatings, id: \.source) { rating in
                    HStack(spacing: 6) {
                        // Icons based on source
                        if rating.source.contains("Rotten") {
                            Image(systemName: "popcorn.fill").foregroundColor(.red)
                        } else if rating.source.contains("Internet Movie") {
                            Text("IMDb").fontWeight(.bold).foregroundColor(.yellow)
                        } else {
                            Image(systemName: "star.fill").foregroundColor(.orange)
                        }
                        
                        Text(rating.value)
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(CinemeltTheme.cream)
                    }
                }
            } else if let score = viewModel.tmdbDetails?.voteAverage {
                // Fallback to TMDB Score
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundColor(CinemeltTheme.accent)
                        .font(.caption)
                    Text(String(format: "%.1f", score))
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(CinemeltTheme.cream)
                }
            }
            
            // Year Logic - Fixed Ambiguity
            // We use a safe map here to extract the year string
            if let year = viewModel.omdbDetails?.year ?? viewModel.tmdbDetails?.displayDate.map({ String($0.prefix(4)) }) {
                Text(year)
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(.gray)
            }
            
            // Runtime
            if let runtime = viewModel.omdbDetails?.runtime {
                Text(runtime)
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(.gray)
            } else if let runtime = viewModel.tmdbDetails?.runtime, runtime > 0 {
                Text(formatRuntime(runtime))
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 30) {
            // Play Button
            Button(action: {
                if let target = viewModel.smartPlayTarget {
                    // Series: Play smart target
                    viewModel.onPlayEpisodeClicked(target)
                } else {
                    // Movie: Check versions or play directly
                    if viewModel.availableVersions.count > 1 {
                        viewModel.showVersionSelector = true
                    } else {
                        onPlay(viewModel.selectedVersion ?? viewModel.channel)
                    }
                }
            }) {
                HStack(spacing: 15) {
                    Image(systemName: viewModel.playButtonIcon)
                    Text(viewModel.playButtonLabel)
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
    
    private var versionSelectorButton: some View {
        Button(action: { viewModel.showVersionSelector = true }) {
            HStack {
                Image(systemName: "square.stack.3d.up")
                Text("Versions (\(viewModel.availableVersions.count))")
                
                if let selected = viewModel.selectedVersion,
                   let option = viewModel.availableVersions.first(where: { $0.id == selected.url }) {
                    Text("- \(option.label)")
                        .foregroundColor(.gray)
                }
            }
            .font(CinemeltTheme.fontBody(22))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(CinemeltCardButtonStyle())
        .focused($focusedField, equals: .version)
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
                        .focusable(true)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 20)
            }
        }
    }
    
    private var similarContentRail: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("You Might Also Like")
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
                .padding(.leading, 80)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(viewModel.similarContent) { item in
                        SimplePosterCard(
                            title: item.title,
                            posterPath: item.posterPath
                        )
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
            .focusSection()
            
            // Episode List
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 50) {
                    ForEach(viewModel.displayedEpisodes) { ep in
                        Button(action: {
                            viewModel.onPlayEpisodeClicked(ep)
                        }) {
                            EpisodeCard(episode: ep)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedField, equals: .episode(ep.id))
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
            .focusSection()
        }
    }
    
    private func formatRuntime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Helper Views

struct SimplePosterCard: View {
    let title: String
    let posterPath: String?
    
    @FocusState private var isFocused: Bool
    
    private let width: CGFloat = 160
    private let height: CGFloat = 240
    
    var body: some View {
        Button(action: {
            print("Selected similar content: \(title)")
        }) {
            ZStack(alignment: .bottom) {
                // Image
                if let path = posterPath {
                    AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w300\(path)")) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.white.opacity(0.1))
                    }
                    .frame(width: width, height: height)
                    .clipped()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.3))
                        .frame(width: width, height: height)
                }
                
                // Focus Overlay
                if isFocused {
                    LinearGradient(
                        colors: [.clear, CinemeltTheme.accent.opacity(0.8)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .transition(.opacity)
                    
                    Text(title)
                        .font(CinemeltTheme.fontBody(18))
                        .foregroundColor(.black)
                        .lineLimit(2)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .cornerRadius(12)
            .frame(width: width, height: height)
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .shadow(color: isFocused ? CinemeltTheme.accent.opacity(0.5) : .black.opacity(0.3), radius: isFocused ? 20 : 5)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isFocused)
    }
}
