import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    // Focus State
    @FocusState private var focusedField: SearchFocus?
    
    enum SearchFocus: Hashable {
        case searchBar
        case scope(SearchViewModel.SearchScope)
        case content // General content focus
    }
    
    // Grid Layout for Live Channels (Optimized for 16:9 cards)
    let channelGridColumns = [
        GridItem(.adaptive(minimum: 280, maximum: 320), spacing: 40)
    ]
    
    init(repository: PrimeFlixRepository, onPlay: @escaping (Channel) -> Void, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(initialScope: .library))
        self.onPlay = onPlay
        self.onBack = onBack
    }
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // MARK: - 1. Search Header (Pinned)
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
                        
                        // Standard Glass Text Field
                        GlassTextField(
                            title: "Search",
                            placeholder: viewModel.selectedScope == .library ? "Movies & Series..." : "Channels & Groups...",
                            text: $viewModel.query,
                            nextFocus: {
                                viewModel.addToHistory(viewModel.query)
                                // Move focus down to content on submit
                                focusedField = .content
                            }
                        )
                        .focused($focusedField, equals: .searchBar)
                        .submitLabel(.search)
                    }
                    
                    // Scope Picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(SearchViewModel.SearchScope.allCases, id: \.self) { scope in
                                Button(action: { viewModel.selectedScope = scope }) {
                                    Text(scope.rawValue)
                                        .font(CinemeltTheme.fontBody(20))
                                        .foregroundColor(viewModel.selectedScope == scope ? .black : CinemeltTheme.cream)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 10)
                                        .background(
                                            viewModel.selectedScope == scope ?
                                            CinemeltTheme.accent : Color.white.opacity(0.1)
                                        )
                                        .cornerRadius(12)
                                }
                                .cinemeltCardStyle()
                                .focused($focusedField, equals: .scope(scope))
                            }
                        }
                        .padding(20) // Bloom space
                    }
                    .focusSection() // Keep scope navigation contained
                }
                // LAYOUT FIX: Align header with content using global margin
                .padding(.horizontal, CinemeltTheme.Layout.margin)
                .padding(.top, 40)
                .background(
                    LinearGradient(colors: [Color.black.opacity(0.9), Color.clear], startPoint: .top, endPoint: .bottom)
                )
                .zIndex(2)
                
                // MARK: - 2. Main Content Area
                // FIX: ScrollViewReader allows programmatic scrolling if needed
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 50) {
                            
                            if viewModel.isLoading {
                                HStack {
                                    Spacer()
                                    CinemeltLoadingIndicator().scaleEffect(1.5)
                                    Spacer()
                                }
                                .padding(.top, 100)
                            }
                            else if viewModel.query.isEmpty {
                                SearchDiscoveryView(
                                    viewModel: viewModel,
                                    onTagSelected: { tag in
                                        viewModel.query = tag
                                        viewModel.addToHistory(tag)
                                    }
                                )
                            }
                            else if viewModel.hasNoResults {
                                noResultsPlaceholder
                            }
                            else {
                                // Results
                                Group {
                                    if viewModel.selectedScope == .library {
                                        libraryResults
                                    } else {
                                        liveTvResults
                                    }
                                }
                                // FIX: Assign a generic focus tag to the results container
                                // so we can restore focus here if needed.
                                .focused($focusedField, equals: .content)
                            }
                        }
                        // CRITICAL: Standardize margins to prevent jumping
                        .standardSafePadding()
                        .padding(.bottom, 100)
                        .id("TopContent")
                    }
                    // FIX: FocusSection ensures scrolling within this view is prioritized
                    // over jumping back up to the search bar.
                    .focusSection()
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
            
            // Smart Focus Restoration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if focusedField == nil {
                    // If we have results (restored session), focus content.
                    // If empty, focus search bar.
                    if !viewModel.movies.isEmpty || !viewModel.liveChannels.isEmpty {
                        focusedField = .content
                    } else {
                        focusedField = .searchBar
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var libraryResults: some View {
        LazyVStack(alignment: .leading, spacing: 60) {
            if !viewModel.movies.isEmpty {
                ResultSection(title: "Movies", items: viewModel.movies, onPlay: onPlay)
            }
            if !viewModel.series.isEmpty {
                ResultSection(title: "Series", items: viewModel.series, onPlay: onPlay)
            }
        }
        // Remove padding here as ResultSection handles it
        .padding(.horizontal, -CinemeltTheme.Layout.margin)
    }
    
    @ViewBuilder
    private var liveTvResults: some View {
        VStack(alignment: .leading, spacing: 40) {
            
            // 1. Categories Row (Pills)
            if !viewModel.liveCategories.isEmpty {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Matching Groups")
                        .font(CinemeltTheme.fontTitle(28))
                        .foregroundColor(CinemeltTheme.accent)
                    
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
                                .cinemeltCardStyle()
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .focusSection()
                }
            }
            
            // 2. Channels Grid
            if !viewModel.liveChannels.isEmpty {
                VStack(alignment: .leading, spacing: 25) {
                    Text("Channels")
                        .font(CinemeltTheme.fontTitle(32))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                    
                    LazyVGrid(columns: channelGridColumns, spacing: 50) {
                        ForEach(viewModel.liveChannels) { channel in
                            Button(action: { onPlay(channel) }) {
                                VStack(spacing: 15) {
                                    AsyncImage(url: URL(string: channel.cover ?? "")) { image in
                                        image.resizable().aspectRatio(contentMode: .fit)
                                    } placeholder: {
                                        Image(systemName: "tv")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray.opacity(0.3))
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
                            .buttonStyle(.card) // Live channels use simple card
                            .padding(10)
                        }
                    }
                }
                .focusSection()
            }
        }
    }
    
    private var noResultsPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 15) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("No results found")
                    .font(CinemeltTheme.fontTitle(28))
                    .foregroundColor(CinemeltTheme.cream)
                
                Button("Clear Search") {
                    viewModel.query = ""
                    focusedField = .searchBar
                }
                .buttonStyle(CinemeltCardButtonStyle())
                .padding(.top, 20)
            }
            Spacer()
        }
        .padding(.top, 80)
    }
}
