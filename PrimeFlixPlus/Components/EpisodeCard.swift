import SwiftUI

struct EpisodeCard: View {
    // This type comes from DetailsViewModel, make sure DetailsViewModel is compiling
    let episode: DetailsViewModel.MergedEpisode
    
    var body: some View {
        HStack(spacing: 20) {
            // 1. Thumbnail
            ZStack {
                if let url = episode.imageUrl {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        CinemeltTheme.backgroundStart
                    }
                } else {
                    ZStack {
                        CinemeltTheme.backgroundStart
                        Image(systemName: "tv")
                            .font(.title)
                            .foregroundColor(CinemeltTheme.accent.opacity(0.5))
                    }
                }
            }
            .frame(width: 240, height: 135) // 16:9 Thumbnail
            .cornerRadius(10)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // 2. Metadata
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(episode.number).")
                        .font(CinemeltTheme.fontTitle(24))
                        .foregroundColor(CinemeltTheme.accent)
                    
                    Text(episode.title)
                        .font(CinemeltTheme.fontTitle(24))
                        .foregroundColor(CinemeltTheme.cream)
                        .lineLimit(1)
                }
                
                Text(episode.overview)
                    .font(CinemeltTheme.fontBody(18))
                    .foregroundColor(.gray)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .padding(.vertical, 8)
            
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
