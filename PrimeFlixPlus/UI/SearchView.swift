import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    // Focus State
    @FocusState private var focusedField: SearchFocus?
    
    enum SearchFocus: Hashable {
        case searchBar
        case scope(SearchViewModel.SearchScope)
    }
    
    // MARK: - Initializer
    // FIX: Added 'repository' to init to satisfy the build error
    init(repository: PrimeFlixRepository, onPlay: @escaping (Channel) -> Void, onBack: @escaping () -> Void) {
        // Initialize ViewModel with the repository immediately
        _viewModel = StateObject(wrappedValue: SearchViewModel(repository: repository))
        self.onPlay = onPlay
        self.onBack = onBack
    }
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // MARK: - 1. Search Header
                VStack(spacing: 20) {
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
                            title: "Search Library",
                            placeholder: "Search Movies, Series, or Live TV...",
                            text: $viewModel.query,
                            nextFocus: {
                                // Save history when user hits Enter
                                viewModel.addToHistory(viewModel.query)
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
                                .buttonStyle(CinemeltCardButtonStyle())
                                .focused($focusedField, equals: .scope(scope))
                            }
                        }
                        .padding(5)
                    }
                    .focusSection()
                }
                .padding(50)
                .background(
                    LinearGradient(colors: [Color.black.opacity(0.9), Color.clear], startPoint: .top, endPoint: .bottom)
                )
                .zIndex(2)
                
                // MARK: - 2. Main Content Area
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
                            // Shows History and Tags
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
                            resultsContent
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.bottom, 100)
                }
                .focusSection()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if focusedField == nil { focusedField = .searchBar }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var resultsContent: some View {
        LazyVStack(alignment: .leading, spacing: 60) {
            if !viewModel.movies.isEmpty {
                ResultSection(title: "Movies", items: viewModel.movies, onPlay: onPlay)
            }
            if !viewModel.series.isEmpty {
                ResultSection(title: "Series", items: viewModel.series, onPlay: onPlay)
            }
            if !viewModel.liveChannels.isEmpty {
                ResultSection(title: "Live Channels", items: viewModel.liveChannels, onPlay: onPlay)
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
            }
            Spacer()
        }
        .padding(.top, 80)
    }
}
