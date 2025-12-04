import SwiftUI

struct SyncStatusOverlay: View {
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        VStack {
            if let message = repository.syncStatusMessage {
                HStack(spacing: 16) {
                    // Status Icon
                    if repository.isErrorState {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.3))
                            .font(.title3)
                    } else if repository.isSyncing {
                        ProgressView()
                            .tint(CinemeltTheme.accent)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(CinemeltTheme.accent)
                            .font(.title3)
                    }
                    
                    // Message
                    Text(message)
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(CinemeltTheme.cream)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                // Glowing border
                .overlay(
                    Capsule()
                        .stroke(
                            repository.isErrorState ? Color.red.opacity(0.5) : CinemeltTheme.accent.opacity(0.5),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: repository.syncStatusMessage)
                .padding(.top, 60) // Safe Area inset
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false) // Let clicks pass through
    }
}
