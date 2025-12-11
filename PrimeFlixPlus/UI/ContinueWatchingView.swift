import SwiftUI

struct ContinueWatchingView: View {
    var onPlay: (Channel) -> Void
    var onBack: () -> Void
    
    @StateObject private var viewModel = ContinueWatchingViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // Focus Management
    @FocusState private var focusedField: CWFocus?
    
    enum CWFocus: Hashable {
        case content
    }
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 50))
                        .foregroundColor(CinemeltTheme.accent)
                    
                    Text("Continue Watching")
                        .font(CinemeltTheme.fontTitle(60))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                    
                    Spacer()
                }
                .padding(.top, 20)
                // ALIGNMENT FIX: Use global margin
                .padding(.horizontal, CinemeltTheme.Layout.margin)
                .padding(.bottom, 20)
                
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        CinemeltLoadingIndicator()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if viewModel.movies.isEmpty && viewModel.series.isEmpty && viewModel.liveChannels.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "deskclock")
                            .font(.system(size: 80))
                            .foregroundColor(CinemeltTheme.accent.opacity(0.3))
                        Text("No history yet.")
                            .cinemeltBody()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 50) {
                            
                            if !viewModel.series.isEmpty {
                                ContinueWatchingLane(title: "Series", items: viewModel.series, onItemClick: onPlay)
                            }
                            
                            if !viewModel.movies.isEmpty {
                                ContinueWatchingLane(title: "Movies", items: viewModel.movies, onItemClick: onPlay)
                            }
                            
                            if !viewModel.liveChannels.isEmpty {
                                ContinueWatchingLane(title: "Live TV", items: viewModel.liveChannels, onItemClick: onPlay)
                            }
                            
                            Spacer().frame(height: 100)
                        }
                        .padding(.top, 20)
                        // Assign focus tag so we can force selection here
                        .focused($focusedField, equals: .content)
                    }
                    // CRITICAL FIX: Safe Padding
                    .standardSafePadding()
                }
            }
        }
        .onAppear {
            viewModel.configure(repository: repository)
            
            // FORCE FOCUS to content
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if focusedField == nil {
                    focusedField = .content
                }
            }
        }
        .onExitCommand { onBack() }
    }
}
