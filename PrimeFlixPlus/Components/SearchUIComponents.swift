import SwiftUI

// MARK: - Result Section
/// Reusable horizontal lane for search results (Movies, Series, Live).
struct ResultSection: View {
    let title: String
    let items: [Channel]
    let onPlay: (Channel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.cream)
                // ALIGNMENT FIX: Match global safe area
                .padding(.leading, CinemeltTheme.Layout.margin)
                .cinemeltGlow()
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(items) { item in
                        MovieCard(channel: item, onClick: { onPlay(item) })
                    }
                }
                // Padding for focus bloom + alignment
                .padding(.vertical, 40)
                .padding(.horizontal, CinemeltTheme.Layout.margin)
            }
            .focusSection() // Ensures focus stays within this lane until exit
        }
    }
}
