import SwiftUI

/// The "Zero State" view that appears when the search bar is empty.
/// Drives discovery via History, Moods, and Genres (Tags).
struct SearchDiscoveryView: View {
    @ObservedObject var viewModel: SearchViewModel
    
    // Action to populate the search bar
    var onTagSelected: (String) -> Void
    
    // MARK: - Data Definitions
    // We hardcode these "Quick Tags" to map to standard Xtream Group names or Keywords.
    // This avoids an expensive database scan on every load.
    private let genres = [
        "Action", "Adventure", "Animation", "Comedy", "Crime",
        "Documentary", "Drama", "Family", "Fantasy", "Horror",
        "Mystery", "Romance", "Sci-Fi", "Thriller", "War", "Western"
    ]
    
    private let moods = [
        "Chill", "Adrenaline", "Feel-Good", "Dark", "Epic", "Romantic", "Scary", "Thoughtful"
    ]
    
    private let collections = [
        "Marvel", "DC", "Star Wars", "Harry Potter", "Lord of the Rings",
        "Pixar", "Disney", "James Bond"
    ]
    
    @FocusState private var focusedTag: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            
            // 1. Recent History (If available)
            if !viewModel.searchHistory.isEmpty {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(CinemeltTheme.accent)
                        Text("Recent")
                            .font(CinemeltTheme.fontTitle(32))
                            .foregroundColor(CinemeltTheme.cream)
                        
                        Spacer()
                        
                        Button("Clear") { viewModel.clearHistory() }
                            .buttonStyle(.plain)
                            .font(CinemeltTheme.fontBody(20))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 50)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(viewModel.searchHistory, id: \.self) { term in
                                Button(action: { onTagSelected(term) }) {
                                    Text(term)
                                        .font(CinemeltTheme.fontBody(24))
                                        .foregroundColor(CinemeltTheme.cream)
                                        .padding(.horizontal, 25)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(12)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                                .focused($focusedTag, equals: "hist_\(term)")
                            }
                        }
                        .padding(.horizontal, 50)
                        .padding(.vertical, 20) // Focus bloom space
                    }
                }
            }
            
            // 2. Collections (Smart Tags)
            tagLane(title: "Collections", icon: "square.stack.3d.up.fill", tags: collections, prefix: "col")
            
            // 3. Moods
            tagLane(title: "Browse by Mood", icon: "sparkles", tags: moods, prefix: "mood")
            
            // 4. Genres
            tagLane(title: "Genres", icon: "film", tags: genres, prefix: "gen")
            
            Spacer(minLength: 50)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Helper Builder
    private func tagLane(title: String, icon: String, tags: [String], prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(CinemeltTheme.accent)
                    .font(.title2)
                Text(title)
                    .font(CinemeltTheme.fontTitle(32))
                    .foregroundColor(CinemeltTheme.cream)
            }
            .padding(.horizontal, 50)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(tags, id: \.self) { tag in
                        Button(action: { onTagSelected(tag) }) {
                            Text(tag)
                                .font(CinemeltTheme.fontBody(22))
                                .fontWeight(.medium)
                                .foregroundColor(CinemeltTheme.cream)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(
                                    ZStack {
                                        CinemeltTheme.glassSurface
                                        // Subtle gradient overlay for "Chips"
                                        LinearGradient(
                                            colors: [.white.opacity(0.05), .clear],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    }
                                )
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedTag, equals: "\(prefix)_\(tag)")
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}
