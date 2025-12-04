import SwiftUI

struct SidebarView: View {
    @Binding var currentSelection: NavigationDestination
    @Namespace private var animationNamespace
    @FocusState private var focusedItem: NavigationDestination?
    
    // Define the menu items
    let menuItems: [(destination: NavigationDestination, icon: String, label: String)] = [
        (.home, "house.fill", "Home"),
        (.search, "magnifyingglass", "Search"),
        (.settings, "gearshape.fill", "Settings"),
        (.addPlaylist, "person.badge.plus", "Profiles")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 1. Logo Section (Top)
            VStack(spacing: 8) {
                Image("CinemeltLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 50)
                    .shadow(color: CinemeltTheme.accent.opacity(0.6), radius: 12, x: 0, y: 0)
                
                // Fallback text if logo fails to load, styled elegantly
                if UIImage(named: "CinemeltLogo") == nil {
                    Text("CINEMELT")
                        .font(CinemeltTheme.fontTitle(26))
                        .tracking(4) // Wide tracking for premium feel
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .padding(.bottom, 60)
            
            // 2. Navigation Items
            VStack(spacing: 20) {
                ForEach(menuItems, id: \.destination.hashValue) { item in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            currentSelection = item.destination
                        }
                    }) {
                        HStack(spacing: 16) {
                            // Icon with glowing effect when active
                            Image(systemName: item.icon)
                                .font(.system(size: 24, weight: .bold))
                                .frame(width: 30)
                                .shadow(color: currentSelection == item.destination ? CinemeltTheme.accent.opacity(0.8) : .clear, radius: 8)
                            
                            // Label
                            Text(item.label)
                                .font(CinemeltTheme.fontBody(26))
                                .fontWeight(currentSelection == item.destination ? .bold : .regular)
                            
                            Spacer()
                            
                            // Small dot indicator for active state
                            if currentSelection == item.destination {
                                Circle()
                                    .fill(CinemeltTheme.accent)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: CinemeltTheme.accent, radius: 4)
                            }
                        }
                        .foregroundColor(
                            focusedItem == item.destination ? .black :
                            currentSelection == item.destination ? CinemeltTheme.cream : .gray
                        )
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        .background(
                            ZStack {
                                // The "Sliding" Background for Active State
                                if currentSelection == item.destination {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.1))
                                        .matchedGeometryEffect(id: "activeTab", in: animationNamespace)
                                }
                                // The Focus Background (handled by button style, but added here for contrast)
                                if focusedItem == item.destination {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(CinemeltTheme.accent)
                                        .shadow(color: CinemeltTheme.accent.opacity(0.5), radius: 10)
                                }
                            }
                        )
                    }
                    .buttonStyle(.card) // Uses system parallax internally
                    .focused($focusedItem, equals: item.destination)
                }
            }
            .padding(.horizontal, 16)
            
            Spacer()
            
            // 3. User / Version Info (Bottom)
            VStack(spacing: 4) {
                Text("v1.0")
                    .font(CinemeltTheme.fontBody(14))
                    .foregroundColor(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .frame(width: 280) // Slightly slimmer for elegance
        .background(
            // Glassmorphic Sidebar Background
            Rectangle()
                .fill(.ultraThinMaterial)
                .background(Color.black.opacity(0.2))
                .ignoresSafeArea()
                .overlay(
                    HStack {
                        Spacer()
                        // Right edge highlight
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom))
                            .frame(width: 1)
                    }
                )
        )
        .zIndex(100)
    }
}
