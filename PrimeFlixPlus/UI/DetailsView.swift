import SwiftUI

struct DetailsView: View {
    @StateObject private var viewModel: DetailsViewModel
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    // UI State for "Read More" text
    @State private var showFullDescription: Bool = false
    
    init(channel: Channel, onPlay: @escaping (Channel) -> Void, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: DetailsViewModel(channel: channel))
        self.onPlay = onPlay
        self.onBack = onBack
    }
    
    // Focus Management
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case description
        case play, watchlist, favorite, version
        case season(Int)
        case episode(String)
        case cast(Int)
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
            
            // Initial focus: Default to Play button
            if focusedField == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .play
                }
            }
        }
        .onExitCommand { onBack() }
        
        // --- POPUPS & INTERACTION ---
        
        // 1. Version Selection Dialog
        .confirmationDialog(
            viewModel.pickerTitle,
            isPresented: $viewModel.showVersionPicker,
            titleVisibility: .visible
        ) {
            ForEach(viewModel.pickerOptions, id: \.id) { option in
                Button(option.label) {
                    viewModel.onPickerSelect?(option.channelStruct)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        
        // 2. Full Description Sheet
        .sheet(isPresented: $showFullDescription) {
            ScrollView {
                Text(viewModel.omdbDetails?.plot ?? viewModel.tmdbDetails?.overview ?? viewModel.channel.overview ?? "")
                    .font(CinemeltTheme.fontBody(32))
                    .foregroundColor(CinemeltTheme.cream)
                    .padding(60)
            }
            .background(CinemeltTheme.mainBackground)
            .ignoresSafeArea()
        }
        
        // 3. Listener for Play Trigger (from ViewModel bubble-up)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PlayChannel"))) { note in
            if let channel = note.object as? Channel {
                onPlay(channel)
            }
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
                                        .init(color: .black.opacity(0.4), location: 0.3),
                                        .init(color: CinemeltTheme.charcoal, location: 0.9)
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
                    Text(viewModel.omdbDetails?.title ?? viewModel.tmdbDetails?.displayTitle ?? viewModel.channel.title)
                        .font(CinemeltTheme.fontTitle(90))
                        .foregroundColor(CinemeltTheme.cream)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 5)
                    
                    metadataRow
                    
                    // Description (Clickable)
                    Button(action: { showFullDescription = true }) {
                        Text(viewModel.omdbDetails?.plot ?? viewModel.tmdbDetails?.overview ?? viewModel.channel.overview ?? "No synopsis available.")
                            .font(CinemeltTheme.fontBody(28))
                            .lineSpacing(8)
                            .foregroundColor(focusedField == .description ? .white : CinemeltTheme.cream.opacity(0.9))
                            .frame(maxWidth: 950, alignment: .leading)
                            .lineLimit(4)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(focusedField == .description ? Color.white.opacity(0.1) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .focused($focusedField, equals: .description)
                }
                .padding(.horizontal, 10) // Small local padding, real margin handled by parent
                .focusSection()
                
                // --- Action Buttons ---
                actionButtons
                    .padding(.horizontal, 10)
                    .focusSection()
                
                // --- Series Content (Seasons & Episodes) ---
                if viewModel.channel.type == "series" || viewModel.channel.type == "series_episode" {
                    seriesContent
                        .zIndex(2)
                }
                
                // --- Cast ---
                if !viewModel.cast.isEmpty {
                    castRail
                }
                
                Spacer(minLength: 150)
            }
            // CRITICAL FIX: Safe Padding for Layout Safety
            .standardSafePadding()
        }
    }
    
    private var metadataRow: some View {
        HStack(spacing: 25) {
            // Quality Badge (Shows Best Available)
            if let best = viewModel.movieVersions.first {
                Badge(text: best.quality)
            } else if let epQuality = viewModel.displayedEpisodes.first?.versions.first?.quality {
                 Badge(text: epQuality) // Show quality of first episode if series
            }
            
            // Ratings (OMDB or TMDB)
            if let score = viewModel.omdbDetails?.imdbRating {
                HStack(spacing: 6) {
                    Text("IMDb").fontWeight(.bold).foregroundColor(.yellow)
                    Text(score).font(CinemeltTheme.fontBody(24)).foregroundColor(CinemeltTheme.cream)
                }
            }
            
            // Year
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
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 30) {
            // Smart Play Button
            Button(action: {
                viewModel.onPlaySmartTarget()
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
            .cinemeltCardStyle() // NEW: Apply Lift Effect
            .focused($focusedField, equals: .play)
            
            // Watch List Button
            Button(action: { viewModel.toggleWatchlist() }) {
                Image(systemName: viewModel.isInWatchlist ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 30))
                    .foregroundColor(viewModel.isInWatchlist ? CinemeltTheme.accent : .white)
                    .padding(22)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .cinemeltCardStyle()
            .focused($focusedField, equals: .watchlist)
            
            // Favorite Button
            Button(action: { viewModel.toggleFavorite() }) {
                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 30))
                    .foregroundColor(viewModel.isFavorite ? CinemeltTheme.accent : .white)
                    .padding(22)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .cinemeltCardStyle()
            .focused($focusedField, equals: .favorite)
            
            // Versions Button (Movies Only - Manual Override)
            if !viewModel.movieVersions.isEmpty {
                Button(action: { viewModel.onPlayMovie() }) {
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                        Text("Versions (\(viewModel.movieVersions.count))")
                    }
                    .font(CinemeltTheme.fontBody(22))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                }
                .cinemeltCardStyle()
                .focused($focusedField, equals: .version)
            }
        }
    }
    
    private var seriesContent: some View {
        VStack(alignment: .leading, spacing: 25) {
            // Season Selector (Tabs)
            if viewModel.seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(viewModel.seasons, id: \.self) { season in
                            Button(action: { Task { await viewModel.loadSeasonContent(season) } }) {
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
                            .cinemeltCardStyle()
                            .focused($focusedField, equals: .season(season))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 20) // Padding for focus bloom
                }
                .focusSection()
            }
            
            // Episode List
            if viewModel.displayedEpisodes.isEmpty {
                Text("No episodes available for this season.")
                    .font(CinemeltTheme.fontBody(20))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 50) {
                        ForEach(viewModel.displayedEpisodes) { ep in
                            Button(action: {
                                viewModel.onPlayEpisode(ep)
                            }) {
                                EpisodeCard(episode: ep)
                            }
                            .cinemeltCardStyle()
                            .frame(width: 350) // Use fixed width to match EpisodeCard
                            .focused($focusedField, equals: .episode(ep.id))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 40)
                }
                .focusSection()
            }
        }
    }
    
    private var castRail: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cast")
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
                .padding(.leading, 10)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(Array(viewModel.cast.prefix(15).enumerated()), id: \.element.id) { index, actor in
                        VStack(spacing: 15) {
                            AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w200\(actor.profilePath ?? "")")) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle().fill(Color.white.opacity(0.1))
                                    .overlay(Text(String(actor.name.prefix(1))).font(.title))
                            }
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                            
                            Text(actor.name)
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                                .lineLimit(1)
                                .frame(width: 140)
                        }
                        .focusable(true)
                        .focused($focusedField, equals: .cast(index))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
        }
        .focusSection()
    }
}
