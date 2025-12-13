import SwiftUI

struct DetailsView: View {
    @StateObject private var viewModel: DetailsViewModel
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    // UI State
    @State private var showFullDescription: Bool = false
    
    // Focus Management
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case description
        case play, watchlist, favorite, version
        case season(Int)
        case episode(String)
        case cast(Int)
    }
    
    init(channel: Channel, onPlay: @escaping (Channel) -> Void, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: DetailsViewModel(channel: channel))
        self.onPlay = onPlay
        self.onBack = onBack
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
                    .font(CinemeltTheme.fontBody(32)) // Description stays large for readability in sheet
                    .foregroundColor(CinemeltTheme.cream)
                    .padding(60)
            }
            .background(CinemeltTheme.mainBackground)
            .ignoresSafeArea()
        }
        
        // 3. Listeners for Playback Triggers
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
            VStack(alignment: .leading, spacing: 30) { // Tightened vertical spacing
                
                Spacer().frame(height: 350)
                
                // --- Title & Metadata ---
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.omdbDetails?.title ?? viewModel.tmdbDetails?.displayTitle ?? viewModel.channel.title)
                        .font(CinemeltTheme.fontTitle(90))
                        .foregroundColor(CinemeltTheme.cream)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 5)
                    
                    metadataRow
                    
                    // Description (Clickable)
                    Button(action: { showFullDescription = true }) {
                        Text(viewModel.omdbDetails?.plot ?? viewModel.tmdbDetails?.overview ?? viewModel.channel.overview ?? "No synopsis available.")
                            .font(CinemeltTheme.fontBody(26))
                            .lineSpacing(6)
                            .foregroundColor(focusedField == .description ? .white : CinemeltTheme.cream.opacity(0.9))
                            .frame(maxWidth: 900, alignment: .leading)
                            .lineLimit(3) // Limit lines to keep UI compact
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(focusedField == .description ? Color.white.opacity(0.1) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .focused($focusedField, equals: .description)
                }
                .padding(.horizontal, 10)
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
                
                Spacer(minLength: 100)
            }
            // CRITICAL FIX: Safe Padding
            .standardSafePadding()
        }
    }
    
    private var metadataRow: some View {
        HStack(spacing: 25) {
            // Quality Badge
            if let best = viewModel.movieVersions.first {
                Badge(text: best.quality)
            } else if let epQuality = viewModel.displayedEpisodes.first?.versions.first?.quality {
                Badge(text: epQuality)
            }
            
            // Ratings
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
        HStack(spacing: 25) {
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
                .padding(.horizontal, 35)
                .padding(.vertical, 16)
                .background(CinemeltTheme.accent)
                .cornerRadius(12)
            }
            .cinemeltCardStyle()
            .focused($focusedField, equals: .play)
            
            // Watch List Button
            Button(action: { viewModel.toggleWatchlist() }) {
                Image(systemName: viewModel.isInWatchlist ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 28))
                    .foregroundColor(viewModel.isInWatchlist ? CinemeltTheme.accent : .white)
                    .padding(18)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .cinemeltCardStyle()
            .focused($focusedField, equals: .watchlist)
            
            // Favorite Button
            Button(action: { viewModel.toggleFavorite() }) {
                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 28))
                    .foregroundColor(viewModel.isFavorite ? CinemeltTheme.accent : .white)
                    .padding(18)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .cinemeltCardStyle()
            .focused($focusedField, equals: .favorite)
            
            // Versions Button
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
        VStack(alignment: .leading, spacing: 20) {
            // Season Selector
            if viewModel.seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(viewModel.seasons, id: \.self) { season in
                            Button(action: { Task { await viewModel.loadSeasonContent(season) } }) {
                                Text("Season \(season)")
                                    .font(CinemeltTheme.fontTitle(22))
                                    .foregroundColor(viewModel.selectedSeason == season ? .black : CinemeltTheme.cream)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(
                                        viewModel.selectedSeason == season ?
                                        CinemeltTheme.accent : Color.white.opacity(0.05)
                                    )
                                    .cornerRadius(20)
                            }
                            .cinemeltCardStyle()
                            .focused($focusedField, equals: .season(season))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 20)
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
                // FIXED: ScrollViewReader for Auto-Scrolling
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 40) {
                            ForEach(viewModel.displayedEpisodes) { ep in
                                Button(action: {
                                    viewModel.onPlayEpisode(ep)
                                }) {
                                    EpisodeCard(episode: ep)
                                }
                                .cinemeltCardStyle()
                                // FIXED: Strict frame constraint to prevent "Way too tall" cards
                                .frame(width: 360, height: 230)
                                .focused($focusedField, equals: .episode(ep.id))
                                .id(ep.id) // ID for scrolling
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 40)
                    }
                    .onAppear {
                        // Scroll to next up episode on load
                        if let target = viewModel.nextUpEpisode {
                            proxy.scrollTo(target.id, anchor: .center)
                        }
                    }
                    .onChange(of: viewModel.displayedEpisodes.count) { _ in
                        // Scroll if season changes
                        if let target = viewModel.nextUpEpisode {
                            proxy.scrollTo(target.id, anchor: .center)
                        }
                    }
                }
                .focusSection()
            }
        }
    }
    
    private var castRail: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Cast")
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
                .padding(.leading, 10)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 30) {
                    ForEach(Array(viewModel.cast.prefix(15).enumerated()), id: \.element.id) { index, actor in
                        VStack(spacing: 10) {
                            AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w200\(actor.profilePath ?? "")")) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle().fill(Color.white.opacity(0.1))
                                    .overlay(Text(String(actor.name.prefix(1))).font(.title))
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                            
                            Text(actor.name)
                                .font(CinemeltTheme.fontBody(18))
                                .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                                .lineLimit(1)
                                .frame(width: 120)
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

// MARK: - Components Helper

struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(CinemeltTheme.fontBody(18))
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CinemeltTheme.accent)
            .cornerRadius(4)
    }
}

// Adapter to use the shared EpisodeCard with the ViewModel struct
extension EpisodeCard {
    init(episode: DetailsViewModel.MergedEpisode) {
        // We create a temporary Channel object for the view display if needed,
        // OR we update EpisodeCard to accept this struct directly.
        // Assuming EpisodeCard has been updated to use MergedEpisode based on previous context.
        // If not, we map:
        let placeholderChannel = Channel(context: PersistenceController.shared.container.viewContext)
        placeholderChannel.title = episode.title
        placeholderChannel.overview = episode.overview
        placeholderChannel.episode = Int16(episode.number)
        placeholderChannel.season = Int16(episode.season)
        placeholderChannel.cover = episode.stillPath?.absoluteString
        // Note: This is a view-only object, not saved
        
        self.init(episode: episode) // Using the struct initializer
    }
}
