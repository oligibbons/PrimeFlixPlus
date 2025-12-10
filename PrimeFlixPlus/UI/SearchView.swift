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
    }
    
    // MARK: - Initializer
    init(onPlay: @escaping (Channel) -> Void, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SearchViewModel())
        self.onPlay = onPlay
        self.onBack = onBack
    }
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // MARK: - 1. Search Header
                VStack(spacing: 20) {
                    // Row A: Back + Input
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
                            nextFocus: { /* Submit action if needed */ }
                        )
                        .focused($focusedField, equals: .searchBar)
                        .submitLabel(.search)
                    }
                    
                    // Row B: Scope Picker (Tabs) - Simplified
                    // Allows user to quickly filter the list below without complex logic
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
                        
                        // A. Loading State
                        if viewModel.isLoading {
                            HStack {
                                Spacer()
                                CinemeltLoadingIndicator().scaleEffect(1.5)
                                Spacer()
                            }
                            .padding(.top, 100)
                        }
                        // B. Zero State (Simple Placeholder)
                        else if viewModel.query.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 20) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 60))
                                        .foregroundColor(CinemeltTheme.accent.opacity(0.5))
                                    Text("Start typing to search...")
                                        .font(CinemeltTheme.fontTitle(32))
                                        .foregroundColor(CinemeltTheme.cream.opacity(0.5))
                                }
                                Spacer()
                            }
                            .padding(.top, 100)
                        }
                        // C. No Results
                        else if viewModel.hasNoResults {
                            noResultsPlaceholder
                        }
                        // D. Results
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
            viewModel.configure(repository: repository)
            // Auto-focus search bar on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if focusedField == nil { focusedField = .searchBar }
            }
        }
    }
    
    // MARK: - Result Views
    
    private var resultsContent: some View {
        LazyVStack(alignment: .leading, spacing: 60) {
            
            // 1. Movies
            if !viewModel.movies.isEmpty {
                ResultSection(title: "Movies", items: viewModel.movies, onPlay: onPlay)
            }
            
            // 2. Series
            if !viewModel.series.isEmpty {
                ResultSection(title: "Series", items: viewModel.series, onPlay: onPlay)
            }
            
            // 3. Live TV
            if !viewModel.liveChannels.isEmpty {
                ResultSection(title: "Live Channels", items: viewModel.liveChannels, onPlay: onPlay)
            }
        }
    }
    
    // MARK: - Placeholders
    
    private var noResultsPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 15) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("No matches found")
                    .font(CinemeltTheme.fontTitle(28))
                    .foregroundColor(CinemeltTheme.cream)
                Text("Try checking your spelling.")
                    .font(CinemeltTheme.fontBody(20))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.top, 80)
    }
}
