import SwiftUI

/// The "Zero State" view that appears when the search bar is empty.
/// Drives discovery via History only (stripped down version).
struct SearchDiscoveryView: View {
    @ObservedObject var viewModel: SearchViewModel
    
    // Action to populate the search bar (used by History items)
    var onTagSelected: (String) -> Void
    
    @FocusState private var focusedTag: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            
            // 1. Recent History (If available)
            if !viewModel.searchHistory.isEmpty {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(CinemeltTheme.accent)
                        Text("Recent")
                            .font(CinemeltTheme.fontTitle(32))
                            .foregroundColor(CinemeltTheme.cream)
                        
                        Spacer()
                        
                        Button("Clear") { viewModel.clearHistory() }
                            .buttonStyle(.plain)
                            .font(CinemeltTheme.fontBody(20))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 50)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(viewModel.searchHistory, id: \.self) { term in
                                Button(action: { onTagSelected(term) }) {
                                    Text(term)
                                        .font(CinemeltTheme.fontBody(24))
                                        .foregroundColor(CinemeltTheme.cream)
                                        .padding(.horizontal, 25)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(12)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                                .focused($focusedTag, equals: "hist_\(term)")
                            }
                        }
                        .padding(.horizontal, 50)
                        .padding(.vertical, 20) // Focus bloom space
                    }
                    .focusSection()
                }
            } else {
                // Empty State hint (Optional)
                VStack {
                    Spacer()
                    Text("Start typing to search...")
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(.gray.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
                .frame(height: 200)
            }
            
            Spacer()
        }
        .padding(.vertical, 20)
    }
}
