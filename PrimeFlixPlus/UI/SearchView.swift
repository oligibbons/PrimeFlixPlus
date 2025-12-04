import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlay: (Channel) -> Void
    
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. Search Header
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.cyan)
                    
                    Text("Search")
                        .font(.custom("Exo2-Bold", size: 40))
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                
                NeonTextField(
                    title: "FIND MOVIES, SERIES, OR LIVE EVENTS",
                    placeholder: "Type to search...",
                    text: $viewModel.searchText
                )
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
            }
            .padding(.horizontal, 60)
            .padding(.top, 40)
            .padding(.bottom, 20)
            .background(
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
            )
            
            // 2. Results Area
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    
                    if viewModel.isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.top, 50)
                    } else if !viewModel.isEmpty {
                        
                        // Movies
                        if !viewModel.movieResults.isEmpty {
                            ResultSection(title: "Movies", items: viewModel.movieResults, onPlay: onPlay)
                        }
                        
                        // Series
                        if !viewModel.seriesResults.isEmpty {
                            ResultSection(title: "Series", items: viewModel.seriesResults, onPlay: onPlay)
                        }
                        
                        // Live TV (Custom Card for EPG info)
                        if !viewModel.liveResults.isEmpty {
                            LiveResultSection(items: viewModel.liveResults, onPlay: onPlay)
                        }
                        
                        // No Results State
                        if viewModel.movieResults.isEmpty && viewModel.seriesResults.isEmpty && viewModel.liveResults.isEmpty {
                            Text("No results found for \"\(viewModel.searchText)\"")
                                .font(.headline)
                                .foregroundColor(.gray)
                                .padding(.leading, 60)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .background(Color.black.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
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
                .padding(.vertical, 20)
            }
        }
    }
}

struct LiveResultSection: View {
    let items: [SearchViewModel.LiveSearchResult]
    let onPlay: (Channel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live TV & Events")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
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
                .padding(.vertical, 20)
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
                .background(Color(white: 0.15))
                
                // Info Area
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.channel.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(isFocused ? .black : .white)
                        .lineLimit(1)
                    
                    if let prog = item.currentProgram {
                        Text("ON NOW: \(prog.title)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(isFocused ? .black.opacity(0.8) : .cyan)
                            .lineLimit(1)
                        
                        Text("\(formatTime(prog.start)) - \(formatTime(prog.end))")
                            .font(.caption2)
                            .foregroundColor(isFocused ? .black.opacity(0.6) : .gray)
                    } else {
                        Text("LIVE")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
                .frame(width: 250, alignment: .leading)
                .background(isFocused ? Color.cyan : Color(white: 0.1))
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
