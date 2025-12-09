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
        case result(String)
    }
    
    // Grid Layout for Results
    let gridLayout = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 40)
    ]
    
    // MARK: - Initializer
    init(initialScope: SearchViewModel.SearchScope = .all, onPlay: @escaping (Channel) -> Void, onBack: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SearchViewModel())
        self.onPlay = onPlay
        self.onBack = onBack
    }
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // MARK: - 1. Search Header (Input, Scopes, Filters)
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
                        
                        GlassTextField(
                            title: "Search Library",
                            placeholder: "Title, Actor, or Director...",
                            text: $viewModel.query,
                            nextFocus: { /* Submit action if needed */ }
                        )
                        .focused($focusedField, equals: .searchBar)
                        .submitLabel(.search)
                    }
                    
                    // Row B: Scope Picker (Tabs)
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
                    
                    // Row C: Smart Filters (Requires SearchFilterBar.swift component)
                    SearchFilterBar(viewModel: viewModel)
                        .padding(.top, 10)
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
                        // B. Zero State (Discovery Engine/Tags/History)
                        else if viewModel.query.isEmpty {
                            // Requires SearchDiscoveryView.swift component
                            SearchDiscoveryView(
                                viewModel: viewModel,
                                onTagSelected: { tag in
                                    viewModel.query = tag
                                }
                            )
                            .transition(.opacity)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if focusedField == nil { focusedField = .searchBar }
            }
        }
    }
    
    // MARK: - Result Views
    
    private var resultsContent: some View {
        LazyVStack(alignment: .leading, spacing: 60) {
            
            // 1. Movies (Priority 1)
            if !viewModel.movies.isEmpty {
                ResultSection(title: "Movies", items: viewModel.movies, onPlay: onPlay)
            }
            
            // 2. Series (Priority 2)
            if !viewModel.series.isEmpty {
                ResultSection(title: "Series", items: viewModel.series, onPlay: onPlay)
            }
            
            // 3. Live TV (Priority 3)
            if !viewModel.liveChannels.isEmpty {
                ResultSection(title: "Live Channels", items: viewModel.liveChannels, onPlay: onPlay)
            }
            
            // 4. Person Spotlight (Moved to Bottom as requested)
            if let person = viewModel.personMatch, !viewModel.personCredits.isEmpty {
                VStack(alignment: .center, spacing: 20) {
                    
                    Divider().background(Color.white.opacity(0.1)).padding(.vertical, 20)
                    
                    Text("Related People")
                        .font(CinemeltTheme.fontTitle(28))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10)
                    
                    // Circular Profile Image
                    if let path = person.profilePath, let url = URL(string: "https://image.tmdb.org/t/p/w400\(path)") {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle().fill(Color.white.opacity(0.1))
                        }
                        .frame(width: 150, height: 150)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(CinemeltTheme.accent, lineWidth: 3))
                        .shadow(color: CinemeltTheme.accent.opacity(0.5), radius: 15)
                    }
                    
                    VStack(spacing: 5) {
                        Text(person.name)
                            .font(CinemeltTheme.fontTitle(32))
                            .foregroundColor(CinemeltTheme.cream)
                            .cinemeltGlow()
                        
                        Text("Known for \(person.role)")
                            .font(CinemeltTheme.fontBody(18))
                            .foregroundColor(.gray)
                    }
                    
                    // The "Collection" Rail
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 40) {
                            ForEach(viewModel.personCredits) { channel in
                                MovieCard(channel: channel) { onPlay(channel) }
                                    .focused($focusedField, equals: .result(channel.id))
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 30)
                    }
                    .focusSection()
                }
                .padding(.vertical, 20)
                .background(Color.white.opacity(0.03))
                .cornerRadius(20)
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
                Text("Try adjusting filters or search terms.")
                    .font(CinemeltTheme.fontBody(20))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.top, 80)
    }
}
