import SwiftUI

struct SyncStatusOverlay: View {
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        VStack {
            if let message = repository.syncStatusMessage {
                HStack(spacing: 16) {
                    if repository.isErrorState {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.3)) // Soft Red
                    } else if repository.isSyncing {
                        ProgressView()
                            .tint(CinemeltTheme.accent)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(CinemeltTheme.accent)
                    }
                    
                    Text(message)
                        .font(CinemeltTheme.fontBody(22))
                        .foregroundColor(CinemeltTheme.cream)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial) // Native tvOS Glass
                .background(Color.black.opacity(0.4))
                .cornerRadius(40)
                // The Cinemelt Glow (Subtle)
                .overlay(
                    RoundedRectangle(cornerRadius: 40)
                        .stroke(
                            repository.isErrorState ? Color.red.opacity(0.4) : CinemeltTheme.accent.opacity(0.4),
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: repository.syncStatusMessage)
                .padding(.top, 60)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false) // Let clicks pass through to the app below
    }
}
