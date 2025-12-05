import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlay: (Channel) -> Void
    
    // Internal focus for the search field to grab attention on appear
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // 1. Global Cinematic Background
            CinemeltTheme.mainBackground
            
            VStack(spacing: 0) {
                
                // 2. The Floating Search Header (Compact)
                // DIRECT TEXT FIELD IMPLEMENTATION (Fixes Focus Trap)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search Library")
                        .font(CinemeltTheme.fontBody(20))
                        .fontWeight(.bold)
                        .foregroundColor(isSearchFieldFocused ? CinemeltTheme.accent : .gray)
                        .padding(.leading, 4)
                        .animation(.easeInOut(duration: 0.2), value: isSearchFieldFocused)
                    
                    TextField("Find movies, series, channels...", text: $viewModel.searchText)
                        .font(CinemeltTheme.fontBody(26))
                        .focused($isSearchFieldFocused)
                        .submitLabel(.done)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(16)
                        // Neon Border Effect
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    isSearchFieldFocused ? CinemeltTheme.accent : Color.white.opacity(0.1),
                                    lineWidth: isSearchFieldFocused ? 2 : 1
                                )
                        )
                        // Bloom Effect
                        .shadow(
                            color: isSearchFieldFocused ? CinemeltTheme.accent.opacity(0.4) : .clear,
                            radius: 15, x: 0, y: 0
                        )
                        .scaleEffect(isSearchFieldFocused ? 1.02 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSearchFieldFocused)
                }
                .frame(maxWidth: 600)
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(
                        colors: [CinemeltTheme.charcoal, CinemeltTheme.charcoal, CinemeltTheme.charcoal.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
                .zIndex(10)
                
                // 3. Results Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        
                        if viewModel.isSearching {
                            HStack {
                                Spacer()
                                VStack(spacing: 20) {
                                    ProgressView()
                                        .tint(CinemeltTheme.accent)
                                        .scaleEffect(2.0)
                                    Text("Searching...")
                                        .cinemeltBody()
                                }
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
                            
                            // Live TV
                            if !viewModel.liveResults.isEmpty {
                                LiveResultSection(items: viewModel.liveResults, onPlay: onPlay)
                            }
                            
                        } else if viewModel.searchText.isEmpty {
                            // Idle State
                            emptyStateView(icon: "magnifyingglass", text: "Start typing to explore...")
                        } else {
                            // No Results
                            emptyStateView(icon: "exclamationmark.magnifyingglass", text: "No results found.")
                        }
                    }
                    .padding(.bottom, 100)
                    .padding(.top, 20)
                    // CRITICAL FIX: This enables diagonal navigation across rows of different lengths
                    .focusSection()
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
    
    // MARK: - Components
    
    private func emptyStateView(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 100))
                    .foregroundColor(CinemeltTheme.accent.opacity(0.2))
                    .shadow(color: CinemeltTheme.accent.opacity(0.2), radius: 20)
                
                Text(text)
                    .font(CinemeltTheme.fontTitle(32))
                    .foregroundColor(CinemeltTheme.cream.opacity(0.5))
            }
            .offset(y: 100)
            Spacer()
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
                .font(CinemeltTheme.fontTitle(36))
                .foregroundColor(CinemeltTheme.cream)
                .cinemeltGlow()
                .padding(.leading, 60)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 60) {
                    ForEach(items) { channel in
                        MovieCard(channel: channel) {
                            onPlay(channel)
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 60)
            }
        }
    }
}

struct LiveResultSection: View {
    let items: [SearchViewModel.LiveSearchResult]
    let onPlay: (Channel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Live TV & Events")
                .font(CinemeltTheme.fontTitle(36))
                .foregroundColor(CinemeltTheme.cream)
                .cinemeltGlow()
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
                .padding(.vertical, 60)
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
                ZStack {
                    AsyncImage(url: URL(string: item.channel.cover ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "tv").font(.largeTitle).foregroundColor(CinemeltTheme.accent.opacity(0.5))
                    }
                }
                .padding(20)
                .frame(width: 280, height: 160)
                .background(Color.white.opacity(0.05))
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.channel.title)
                            .font(CinemeltTheme.fontBody(22))
                            .fontWeight(.bold)
                            .foregroundColor(isFocused ? .black : CinemeltTheme.cream)
                            .lineLimit(1)
                        Spacer()
                    }
                    
                    if let prog = item.currentProgram {
                        Text("ON NOW: \(prog.title)")
                            .font(CinemeltTheme.fontBody(18))
                            .fontWeight(.bold)
                            .foregroundColor(isFocused ? .black.opacity(0.8) : CinemeltTheme.accent)
                            .lineLimit(1)
                        
                        HStack {
                            Text("\(formatTime(prog.start)) - \(formatTime(prog.end))")
                                .font(CinemeltTheme.fontBody(16))
                                .foregroundColor(isFocused ? .black.opacity(0.6) : .gray)
                            
                            Spacer()
                            if prog.isLiveNow {
                                Capsule()
                                    .fill(CinemeltTheme.accent)
                                    .frame(width: 60, height: 4)
                            }
                        }
                    } else {
                        Text("LIVE STREAM")
                            .font(CinemeltTheme.fontBody(16))
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                    }
                }
                .padding(16)
                .frame(width: 280, alignment: .leading)
                .background(isFocused ? CinemeltTheme.accent : CinemeltTheme.backgroundEnd.opacity(0.8))
            }
            .frame(width: 280)
        }
        .buttonStyle(CinemeltCardButtonStyle())
        .focused($isFocused)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isFocused ? Color.white.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
