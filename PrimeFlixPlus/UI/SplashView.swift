import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // 1. Cinematic Background
            CinemeltTheme.mainBackground
            
            VStack(spacing: 40) {
                // 2. Pulsing Logo
                // Ensure "CinemeltLogo" exists in Assets, or this will just be empty (but won't crash)
                Image("CinemeltLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 350, height: 350)
                    .scaleEffect(isAnimating ? 1.05 : 1.0)
                    // Deep Amber Shadow for atmosphere
                    .shadow(color: CinemeltTheme.accent.opacity(0.6), radius: isAnimating ? 60 : 30)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimating)
                
                // 3. Brand Text
                Text("CINEMELT")
                    .font(CinemeltTheme.fontTitle(80))
                    .foregroundColor(CinemeltTheme.cream)
                    .cinemeltGlow()
                    .opacity(isAnimating ? 1 : 0.8)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimating)
                
                // 4. Loader
                ProgressView()
                    .tint(CinemeltTheme.accent)
                    .scaleEffect(2.0)
                    .padding(.top, 40)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
