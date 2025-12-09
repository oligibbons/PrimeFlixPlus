import SwiftUI

/// A toggle bar that allows users to refine search results.
/// e.g. "Only 4K", "Hide Live TV".
struct SearchFilterBar: View {
    @ObservedObject var viewModel: SearchViewModel
    
    @FocusState private var focusedFilter: String?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                
                // 1. 4K / UHD Filter (The "Cleaner")
                filterToggle(
                    title: "4K Only",
                    icon: "4k.tv.fill",
                    isOn: Binding(
                        get: { viewModel.activeFilters.only4K },
                        set: { viewModel.activeFilters.only4K = $0 }
                    ),
                    id: "4k"
                )
                
                // 2. Movies Only
                filterToggle(
                    title: "Movies",
                    icon: "film.fill",
                    isOn: Binding(
                        get: { viewModel.activeFilters.onlyMovies },
                        set: {
                            viewModel.activeFilters.onlyMovies = $0
                            if $0 { viewModel.activeFilters.onlySeries = false } // Mutually exclusive suggestion
                        }
                    ),
                    id: "movies"
                )
                
                // 3. Series Only
                filterToggle(
                    title: "Series",
                    icon: "tv.inset.filled",
                    isOn: Binding(
                        get: { viewModel.activeFilters.onlySeries },
                        set: {
                            viewModel.activeFilters.onlySeries = $0
                            if $0 { viewModel.activeFilters.onlyMovies = false }
                        }
                    ),
                    id: "series"
                )
                
                // 4. Live TV Filter
                filterToggle(
                    title: "Live TV",
                    icon: "antenna.radiowaves.left.and.right",
                    isOn: Binding(
                        get: { viewModel.activeFilters.onlyLive },
                        set: { viewModel.activeFilters.onlyLive = $0 }
                    ),
                    id: "live"
                )
                
                // Visual Separator
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 30)
                
                // Reset Button (Only appears if filters are active)
                if viewModel.activeFilters.hasActiveFilters {
                    Button(action: {
                        withAnimation {
                            viewModel.activeFilters = .init() // Reset to defaults
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Reset")
                        }
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 50)
            .padding(.vertical, 10)
        }
    }
    
    // MARK: - Component
    
    private func filterToggle(title: String, icon: String, isOn: Binding<Bool>, id: String) -> some View {
        Button(action: {
            withAnimation { isOn.wrappedValue.toggle() }
        }) {
            HStack(spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isOn.wrappedValue ? CinemeltTheme.accent : .gray)
                    .font(.title3)
                
                Image(systemName: icon)
                    .foregroundColor(isOn.wrappedValue ? .white : .gray)
                
                Text(title)
                    .font(CinemeltTheme.fontBody(20))
                    .fontWeight(isOn.wrappedValue ? .bold : .regular)
                    .foregroundColor(isOn.wrappedValue ? .white : .gray)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOn.wrappedValue ? Color.white.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isOn.wrappedValue ? CinemeltTheme.accent.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(CinemeltCardButtonStyle())
        .focused($focusedFilter, equals: id)
    }
}
