import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    @FocusState private var isSearchFieldFocused: Bool
    @FocusState private var focusedScope: SearchViewModel.SearchScope?
    
    let channelGridColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 40)
    ]
    
    // MARK: - Initializer
    init(initialScope: SearchViewModel.SearchScope = .library, onPlay: @escaping (Channel) -> Void, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(initialScope: initialScope))
        self.onPlay = onPlay
        self.onBack = onBack
    }
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                
                // MARK: - Header & Input
                VStack(spacing: 25) {
                    HStack(spacing: 20) {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.title2)
                                .foregroundColor(CinemeltTheme.cream)
                                .padding(12)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.card)
                        
                        // FIX: Updated to match GlassTextField signature (removed icon, added title/nextFocus)
                        GlassTextField(
                            title: "Search",
                            placeholder: viewModel.selectedScope == .library ? "Movies & Series" : "Channels",
                            text: $viewModel.query,
                            nextFocus: {
                                // Optional: Handle explicit submit if needed
                            }
                        )
                        .focused($isSearchFieldFocused)
                        .submitLabel(.search)
                    }
                    
                    // Scope Picker
                    Picker("Search Scope", selection: $viewModel.selectedScope) {
                        ForEach(SearchViewModel.SearchScope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 500)
                    .focused($focusedScope, equals: viewModel.selectedScope)
                }
                .padding(.horizontal, 50)
                .padding(.top, 40)
                .padding(.bottom, 40)
                .background(
                    LinearGradient(colors: [Color.black.opacity(0.8), Color.clear], startPoint: .top, endPoint: .bottom)
                )
                
                // MARK: - Results
                ScrollView {
                    VStack(alignment: .leading, spacing: 50) {
                        
                        if viewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView().tint(CinemeltTheme.accent).scaleEffect(2.0)
                                Spacer()
                            }
                            .padding(.top, 100)
                        } else if viewModel.query.isEmpty {
                            emptyStateView
                        } else if viewModel.hasNoResults {
                            noResultsView
                        } else {
                            if viewModel.selectedScope == .library {
                                libraryResults
                            } else {
                                liveTvResults
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.bottom, 100)
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isSearchFieldFocused = true
            }
        }
    }
    
    // MARK: - View Components
    
    private var emptyStateView: some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 80))
                    .foregroundColor(CinemeltTheme.accent.opacity(0.3))
                Text("What are we watching?")
                    .font(CinemeltTheme.fontTitle(36))
                    .foregroundColor(CinemeltTheme.cream)
                Text("Search for content across your library.")
                    .font(CinemeltTheme.fontBody(20))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.top, 100)
    }
    
    private var noResultsView: some View {
        HStack {
            Spacer()
            VStack(spacing: 15) {
                Image(systemName: "exclamationmark.magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("No matches found")
                    .font(CinemeltTheme.fontTitle(28))
                    .foregroundColor(CinemeltTheme.cream)
            }
            Spacer()
        }
        .padding(.top, 80)
    }
    
    @ViewBuilder
    private var libraryResults: some View {
        if !viewModel.movies.isEmpty {
            ResultSection(title: "Movies", items: viewModel.movies, onPlay: onPlay)
        }
        if !viewModel.series.isEmpty {
            ResultSection(title: "Series", items: viewModel.series, onPlay: onPlay)
        }
    }
    
    @ViewBuilder
    private var liveTvResults: some View {
        if !viewModel.liveCategories.isEmpty {
            VStack(alignment: .leading, spacing: 15) {
                Text("Matching Categories")
                    .font(CinemeltTheme.fontTitle(28))
                    .foregroundColor(CinemeltTheme.accent)
                    .padding(.leading, 10)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(viewModel.liveCategories, id: \.self) { category in
                            Button(action: {
                                withAnimation { viewModel.refineSearch(to: category) }
                            }) {
                                Text(category)
                                    .font(CinemeltTheme.fontBody(20))
                                    .fontWeight(.medium)
                                    .foregroundColor(CinemeltTheme.cream)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 20)
                }
            }
        }
        
        if !viewModel.liveChannels.isEmpty {
            VStack(alignment: .leading, spacing: 25) {
                Text("Channels")
                    .font(CinemeltTheme.fontTitle(32))
                    .foregroundColor(CinemeltTheme.cream)
                    .cinemeltGlow()
                
                LazyVGrid(columns: channelGridColumns, spacing: 50) {
                    ForEach(viewModel.liveChannels) { channel in
                        // FIX: Replaced tap gesture with native tvOS Button for focus support
                        Button(action: { onPlay(channel) }) {
                            VStack(spacing: 15) {
                                // FIX: Use 'cover' as 'logo' does not exist on Channel entity
                                AsyncImage(url: URL(string: channel.cover ?? "")) { image in
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Image(systemName: "tv").font(.system(size: 40)).foregroundColor(.gray.opacity(0.3))
                                }
                                .frame(width: 120, height: 120)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(20)
                                .shadow(radius: 5)
                                
                                Text(channel.title)
                                    .font(CinemeltTheme.fontBody(18))
                                    .foregroundColor(CinemeltTheme.cream)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.card)
                        .padding(10)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct ResultSection: View {
    let title: String
    let items: [Channel]
    let onPlay: (Channel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title).font(CinemeltTheme.fontTitle(32)).foregroundColor(CinemeltTheme.cream)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(items) { item in
                        // FIX: Removed invalid closure argument `_ in`
                        MovieCard(channel: item, onClick: { onPlay(item) })
                    }
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 20)
            }
        }
    }
}
