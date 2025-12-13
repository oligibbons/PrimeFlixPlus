import SwiftUI

struct SyncStatusOverlay: View {
    @EnvironmentObject var repository: PrimeFlixRepository
    
    // Internal state to handle the "Ghost" issue
    @State private var isVisible: Bool = false
    
    var body: some View {
        ZStack {
            if isVisible {
                VStack(spacing: 15) {
                    // Spinner
                    CinemeltLoadingIndicator()
                        .frame(width: 40, height: 40)
                    
                    // Text
                    VStack(spacing: 5) {
                        Text(statusTitle)
                            .font(CinemeltTheme.fontTitle(28))
                            .foregroundColor(CinemeltTheme.cream)
                        
                        if let msg = repository.syncStatusMessage {
                            Text(msg)
                                .font(CinemeltTheme.fontBody(20))
                                .foregroundColor(CinemeltTheme.cream.opacity(0.6))
                        }
                    }
                }
                .padding(25)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(CinemeltTheme.accent.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 40)
            }
        }
        .onChange(of: repository.isSyncing) { _ in updateVisibility() }
        .onChange(of: repository.syncStatusMessage) { _ in updateVisibility() }
        .onAppear {
            updateVisibility()
        }
    }
    
    private var statusTitle: String {
        if repository.isInitialSync { return "Setup in Progress" }
        return "Updating Library"
    }
    
    private func updateVisibility() {
        // Show if we are syncing OR if there is a lingering status message (e.g. "Enriching...")
        let shouldShow = repository.isSyncing || repository.syncStatusMessage != nil
        
        withAnimation(.spring()) {
            self.isVisible = shouldShow
        }
        
        // Safety Fallback: Force hide if status clears but UI gets stuck
        if !shouldShow && isVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation { self.isVisible = false }
            }
        }
    }
}
