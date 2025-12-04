import SwiftUI

struct ManageCategoriesView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""
    
    // Filter categories based on search text (searches both raw and clean names)
    var filteredCategories: [String] {
        if searchText.isEmpty {
            return viewModel.allCategories
        } else {
            return viewModel.allCategories.filter {
                $0.localizedCaseInsensitiveContains(searchText) ||
                viewModel.cleanName($0).localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                Text("Manage Categories")
                    .font(CinemeltTheme.fontTitle(50))
                    .foregroundColor(CinemeltTheme.cream)
                    .cinemeltGlow()
                    .padding(.top, 20)
                
                Text("Uncheck categories to hide them from your Home Screen.")
                    .font(CinemeltTheme.fontBody(22))
                    .foregroundColor(.gray)
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search...", text: $searchText)
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(.white)
                }
                .padding(16)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .frame(maxWidth: 600)
                .padding(.vertical, 20)
                
                // Grid of Toggles
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 350))], spacing: 30) {
                        ForEach(filteredCategories, id: \.self) { category in
                            let isHidden = viewModel.isHidden(category)
                            let clean = viewModel.cleanName(category)
                            
                            Button(action: {
                                viewModel.toggleCategoryVisibility(category)
                            }) {
                                HStack {
                                    // Status Icon
                                    Image(systemName: isHidden ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(isHidden ? .gray : CinemeltTheme.accent)
                                        .font(.title2)
                                        .frame(width: 40)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        // Primary: Clean Name (e.g. "Animation")
                                        Text(clean)
                                            .font(CinemeltTheme.fontBody(22))
                                            .fontWeight(.medium)
                                            .foregroundColor(isHidden ? .gray : CinemeltTheme.cream)
                                            .lineLimit(1)
                                        
                                        // Secondary: Raw Name (e.g. "EN | Animation") - ONLY if different
                                        if clean != category {
                                            Text(category)
                                                .font(CinemeltTheme.fontBody(14))
                                                .foregroundColor(.gray.opacity(0.6))
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    
                                    // Checkbox style
                                    Image(systemName: isHidden ? "square" : "checkmark.square.fill")
                                        .foregroundColor(isHidden ? .gray : CinemeltTheme.accent)
                                        .font(.title2)
                                }
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(isHidden ? 0.02 : 0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isHidden ? Color.white.opacity(0.1) : CinemeltTheme.accent.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .opacity(isHidden ? 0.6 : 1.0) // Dim hidden items
                        }
                    }
                    .padding(60)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}
