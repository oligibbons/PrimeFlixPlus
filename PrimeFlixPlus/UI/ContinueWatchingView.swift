import SwiftUI

struct ContinueWatchingView: View {
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    @EnvironmentObject var repository: PrimeFlixRepository
    @StateObject private var viewModel = ContinueWatchingViewModel()
    
    // Grid Layout: Adaptive to fill screen width efficiently
    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 40)
    ]
    
    var body: some View {
        ZStack {
            // Background
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            if viewModel.isLoading {
                CinemeltLoadingIndicator()
            } else if viewModel.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Header
                        HStack {
                            Image(systemName: "play.tv.fill")
                                .foregroundColor(CinemeltTheme.accent)
                                .font(.title2)
                            Text("Continue Watching")
                                .font(CinemeltTheme.fontTitle(40))
                                .foregroundColor(CinemeltTheme.cream)
                                .cinemeltGlow()
                        }
                        .padding(.horizontal, CinemeltTheme.Layout.margin)
                        .padding(.top, 40)
                        
                        // Grid
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(viewModel.items, id: \.url) { channel in
                                // Usage of shared component from HomeComponents.swift
                                ContinueWatchingCard(channel: channel) {
                                    onPlay(channel)
                                }
                                // CONTEXT MENU: Long Press to Remove
                                .contextMenu {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            viewModel.removeFromHistory(channel)
                                        }
                                    } label: {
                                        Label("Remove from History", systemImage: "trash")
                                    }
                                    
                                    Button {
                                        repository.toggleFavorite(channel)
                                    } label: {
                                        Label(channel.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: channel.isFavorite ? "heart.slash" : "heart")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, CinemeltTheme.Layout.margin)
                        .padding(.bottom, 60)
                    }
                }
                .focusSection()
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
        }
        .onExitCommand {
            onBack()
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "popcorn")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No unfinished business")
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream.opacity(0.8))
            
            Text("Movies and shows you start (but don't finish)\nwill appear here automatically.")
                .font(CinemeltTheme.fontBody(24))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }
}
