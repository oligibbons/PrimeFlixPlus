import SwiftUI

struct VPNWarningView: View {
    var onProceed: () -> Void
    var onCancel: () -> Void
    
    @FocusState private var focusedButton: Bool
    
    var body: some View {
        ZStack {
            // 1. Dimmed Background
            Color.black.opacity(0.8).ignoresSafeArea()
            
            // 2. Alert Card
            VStack(spacing: 40) {
                
                // Icon
                Image(systemName: "lock.slash.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.red)
                    .shadow(color: .red.opacity(0.5), radius: 20)
                
                // Text Content
                VStack(spacing: 20) {
                    Text("Unprotected Connection")
                        .font(CinemeltTheme.fontTitle(50))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                    
                    Text("Warning - you do not currently have a VPN active on this device.\n\nYour streaming activity may be visible to your ISP.")
                        .font(CinemeltTheme.fontBody(26))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // Actions
                HStack(spacing: 40) {
                    Button(action: onCancel) {
                        HStack {
                            Image(systemName: "arrow.left")
                            Text("Return")
                        }
                        .font(CinemeltTheme.fontTitle(28))
                        .foregroundColor(CinemeltTheme.cream)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                    .focused($focusedButton) // Default focus
                    
                    Button(action: onProceed) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Proceed Anyway")
                        }
                        .font(CinemeltTheme.fontTitle(28))
                        .foregroundColor(.black)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(CinemeltTheme.accent) // Amber warning color
                        .cornerRadius(12)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                }
            }
            .padding(60)
            .background(.ultraThinMaterial)
            .background(CinemeltTheme.charcoal.opacity(0.8))
            .cornerRadius(40)
            .overlay(
                RoundedRectangle(cornerRadius: 40)
                    .stroke(Color.red.opacity(0.3), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.6), radius: 50)
            .frame(maxWidth: 900)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        .onAppear {
            // Ensure focus lands on the "Return" button by default for safety
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedButton = true
            }
        }
    }
}
