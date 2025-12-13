import SwiftUI

struct MovieCard: View {
    let channel: Channel
    let onClick: () -> Void
    var onFocus: (() -> Void)? = nil
    
    @FocusState private var isFocused: Bool
    
    // Using standard TV layout constants from CinemeltStyle
    private let width: CGFloat = CinemeltTheme.Layout.posterWidth
    private let height: CGFloat = CinemeltTheme.Layout.posterHeight
    
    var body: some View {
        Button(action: onClick) {
            // The ZStack (Label) must effectively fill the frame for the custom style to work.
            ZStack(alignment: .bottom) {
                
                // 1. Image Layer
                AsyncImage(url: URL(string: channel.cover ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                    case .failure, .empty:
                        fallbackView
                    @unknown default:
                        fallbackView
                    }
                }
                
                // 2. Metadata Overlay (Only reveals on focus)
                if isFocused {
                    LinearGradient(
                        colors: [.clear, CinemeltTheme.charcoal.opacity(0.95)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        
                        Text(channel.title)
                            .font(CinemeltTheme.fontTitle(28))
                            .foregroundColor(CinemeltTheme.cream)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black, radius: 2, x: 0, y: 1)
                        
                        if let quality = channel.quality {
                            Text(quality.uppercased())
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(CinemeltTheme.accent)
                                .fontWeight(.bold)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
            }
            // CRITICAL: Explicit frame required for tvOS focus engine
            .frame(width: width, height: height)
            .background(CinemeltTheme.charcoal)
            .cornerRadius(12)
            // REMOVED: The white border overlay.
            // Focus state is now indicated purely by the scale/shadow in .cinemeltCardStyle()
        }
        // Apply the custom "Lift" style from CinemeltStyle.swift
        .cinemeltCardStyle()
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused { onFocus?() }
        }
    }
    
    private var fallbackView: some View {
        ZStack {
            CinemeltTheme.coffee
            
            VStack(spacing: 10) {
                Image(systemName: "film")
                    .font(.system(size: 60))
                    .foregroundColor(CinemeltTheme.cream.opacity(0.2))
                
                Text(String(channel.title.prefix(1)))
                    .font(CinemeltTheme.fontTitle(80))
                    .foregroundColor(CinemeltTheme.cream.opacity(0.1))
            }
        }
        .frame(width: width, height: height)
    }
}
