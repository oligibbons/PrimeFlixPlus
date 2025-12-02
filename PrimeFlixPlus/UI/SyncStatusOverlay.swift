import SwiftUI

struct SyncStatusOverlay: View {
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        VStack {
            if let message = repository.syncStatusMessage {
                HStack(spacing: 15) {
                    if repository.isErrorState {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    } else if repository.isSyncing {
                        ProgressView()
                            .tint(.cyan)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    Text(message)
                        .font(.headline)
                        .foregroundColor(repository.isErrorState ? .red : .white)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.4))
                .cornerRadius(40)
                .overlay(
                    RoundedRectangle(cornerRadius: 40)
                        .stroke(repository.isErrorState ? Color.red.opacity(0.5) : Color.cyan.opacity(0.5), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(), value: repository.syncStatusMessage)
                .padding(.top, 60)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
