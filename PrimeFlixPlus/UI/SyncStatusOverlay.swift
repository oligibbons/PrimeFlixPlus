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
                        Text(statusText)
                            .font(CinemeltTheme.fontTitle(28))
                            .foregroundColor(CinemeltTheme.cream)
                        
                        if repository.enrichmentQueue.count > 0 {
                            Text("\(repository.enrichmentQueue.count) items remaining")
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
        .onChange(of: repository.isSyncing) { newValue in
            updateVisibility()
        }
        .onChange(of: repository.enrichmentQueue.count) { newValue in
            updateVisibility()
        }
        .onAppear {
            updateVisibility()
        }
    }
    
    private var statusText: String {
        if repository.isSyncing { return "Updating Library..." }
        if !repository.enrichmentQueue.isEmpty { return "Enriching Metadata..." }
        return "Complete"
    }
    
    private func updateVisibility() {
        let shouldShow = repository.isSyncing || !repository.enrichmentQueue.isEmpty
        
        withAnimation(.spring()) {
            self.isVisible = shouldShow
        }
        
        // Safety Fallback: If it says 0 items but is still showing, force hide after 2 seconds
        if !shouldShow && isVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation { self.isVisible = false }
            }
        }
    }
}
