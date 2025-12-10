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
                .padding(.leading, 50) // Align with grid padding
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(items) { item in
                        MovieCard(channel: item, onClick: { onPlay(item) })
                    }
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 50)
            }
            .focusSection() // Ensures focus stays within this lane until exit
        }
    }
}
