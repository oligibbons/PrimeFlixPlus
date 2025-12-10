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
    
    // Grid Layout for Live Channels
    let channelGridColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 40)
    ]
    
    // MARK: - Initializer
    // We remove the repository from init because we use @EnvironmentObject now (cleaner)
    init(repository: PrimeFlixRepository, onPlay: @escaping (Channel) -> Void, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(initialScope: .library))
        self.onPlay = onPlay
        self.onBack = onBack
    }
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // MARK: - 1. Search Header
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
                .focusSection()
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if focusedField == nil { focusedField = .searchBar }
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
                                .buttonStyle(CinemeltCardButtonStyle())
                            }
                        }
                        .padding(.horizontal, 10)
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
                            .buttonStyle(.card)
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
            }
            Spacer()
        }
        .padding(.top, 80)
    }
}
