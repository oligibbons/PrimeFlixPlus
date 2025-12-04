import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlay: (Channel) -> Void
    
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. Glassmorphic Search Header
            VStack(spacing: 20) {
                HStack(spacing: 15) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(isSearchFieldFocused ? CinemeltTheme.accent : .gray)
                    
                    TextField("Search movies, series...", text: $viewModel.searchText)
                        .font(CinemeltTheme.fontBody(30))
                        .focused($isSearchFieldFocused)
                        .submitLabel(.search)
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSearchFieldFocused ? CinemeltTheme.accent.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 2)
                )
                .shadow(color: isSearchFieldFocused ? CinemeltTheme.accent.opacity(0.3) : .clear, radius: 15)
                .padding(.horizontal, 100)
                .padding(.top, 40)
            }
            .padding(.bottom, 20)
            .background(
                LinearGradient(colors: [CinemeltTheme.backgroundStart, .clear], startPoint: .top, endPoint: .bottom)
            )
            .zIndex(1)
            
            // 2. Results Area
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    
                    if viewModel.isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(CinemeltTheme.accent)
                                .scaleEffect(1.5)
                            Spacer()
                        }
                        .padding(.top, 100)
                    } else if !viewModel.isEmpty {
                        
                        // Movies
                        if !viewModel.movieResults.isEmpty {
                            ResultSection(title: "Movies", items: viewModel.movieResults, onPlay: onPlay)
                        }
                        
                        // Series
                        if !viewModel.seriesResults.isEmpty {
                            ResultSection(title: "Series", items: viewModel.seriesResults, onPlay: onPlay)
                        }
                        
                        // Live TV (Custom Section)
                        if !viewModel.liveResults.isEmpty {
                            LiveResultSection(items: viewModel.liveResults, onPlay: onPlay)
                        }
                        
                    } else if !viewModel.searchText.isEmpty {
                        // No Results State
                        HStack {
                            Spacer()
                            VStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("No results found for \"\(viewModel.searchText)\"")
                                    .font(CinemeltTheme.fontBody(24))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.top, 100)
                    }
                }
                .padding(.bottom, 100)
                .padding(.top, 20)
            }
        }
        .background(CinemeltTheme.mainBackground.ignoresSafeArea())
        .onAppear {
            viewModel.configure(repository: repository)
            // Auto-focus search on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isSearchFieldFocused = true
            }
        }
    }
}

// MARK: - Subviews

struct ResultSection: View {
    let title: String
    let items: [Channel]
    let onPlay: (Channel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(CinemeltTheme.fontTitle(28))
                .foregroundColor(CinemeltTheme.cream)
                .padding(.leading, 60)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(items) { channel in
                        MovieCard(channel: channel) {
                            onPlay(channel)
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30) // Focus expansion space
            }
        }
    }
}

struct LiveResultSection: View {
    let items: [SearchViewModel.LiveSearchResult]
    let onPlay: (Channel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Live TV & Events")
                .font(CinemeltTheme.fontTitle(28))
                .foregroundColor(CinemeltTheme.cream)
                .padding(.leading, 60)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(items) { item in
                        LiveSearchCard(item: item) {
                            onPlay(item.channel)
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)
            }
        }
    }
}

struct LiveSearchCard: View {
    let item: SearchViewModel.LiveSearchResult
    let onClick: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: onClick) {
            VStack(spacing: 0) {
                // Icon Area
                ZStack {
                    AsyncImage(url: URL(string: item.channel.cover ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "tv").font(.largeTitle).foregroundColor(.gray)
                    }
                }
                .padding(20)
                .frame(width: 250, height: 140)
                .background(Color.white.opacity(0.05))
                
                // Info Area
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.channel.title)
                        .font(CinemeltTheme.fontBody(20))
                        .fontWeight(.bold)
                        .foregroundColor(isFocused ? .black : CinemeltTheme.cream)
                        .lineLimit(1)
                    
                    if let prog = item.currentProgram {
                        Text("ON NOW: \(prog.title)")
                            .font(CinemeltTheme.fontBody(16))
                            .fontWeight(.bold)
                            .foregroundColor(isFocused ? .black.opacity(0.8) : CinemeltTheme.accent)
                            .lineLimit(1)
                        
                        Text("\(formatTime(prog.start)) - \(formatTime(prog.end))")
                            .font(CinemeltTheme.fontBody(14))
                            .foregroundColor(isFocused ? .black.opacity(0.6) : .gray)
                    } else {
                        Text("LIVE")
                            .font(CinemeltTheme.fontBody(16))
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
                .frame(width: 250, alignment: .leading)
                .background(isFocused ? CinemeltTheme.accent : CinemeltTheme.backgroundEnd.opacity(0.5))
            }
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .frame(width: 250)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(), value: isFocused)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
