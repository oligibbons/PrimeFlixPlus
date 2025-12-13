import SwiftUI

struct VPNWarningView: View {
    var onProceed: () -> Void
    var onCancel: () -> Void
    
    @FocusState private var focusedButton: Bool
    
    var body: some View {
        ZStack {
            // 1. Dimmed Background
            CinemeltTheme.mainBackground.opacity(0.95).ignoresSafeArea()
            
            // 2. Alert Card
            VStack(spacing: 40) {
                
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 160, height: 160)
                    
                    Image(systemName: "lock.open.trianglebadge.exclamationmark.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.red)
                        .shadow(color: .red.opacity(0.5), radius: 20)
                }
                .padding(.top, 20)
                
                // Text Content
                VStack(spacing: 15) {
                    Text("Connection Privacy")
                        .font(CinemeltTheme.fontTitle(48))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                    
                    Text("No active VPN detected. Your streaming activity may be visible to your ISP.")
                        .font(CinemeltTheme.fontBody(26))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Actions
                HStack(spacing: 40) {
                    Button(action: onCancel) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Cancel")
                        }
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(CinemeltTheme.cream)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                    .focused($focusedButton) // Default focus
                    
                    Button(action: onProceed) {
                        HStack {
                            Text("Continue Anyway")
                            Image(systemName: "arrow.right")
                        }
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(.black)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 14)
                        .background(CinemeltTheme.accent)
                        .cornerRadius(12)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                }
                .padding(.bottom, 20)
            }
            .padding(50)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [CinemeltTheme.charcoal.opacity(0.5), Color.black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .cornerRadius(30)
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.8), radius: 50)
            .frame(maxWidth: 800)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        .onAppear {
            // Ensure focus lands on the "Cancel" button by default
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedButton = true
            }
        }
    }
}
