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
        VStack(alignment: .center, spacing: 0) {
            
            // 1. Logo (Compact & Glowing)
            VStack(spacing: 5) {
                Image("CinemeltLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)
                    .shadow(color: CinemeltTheme.accent.opacity(0.8), radius: 15, x: 0, y: 0)
            }
            .padding(.top, 50)
            .padding(.bottom, 50)
            
            // 2. Navigation Items
            VStack(spacing: 25) {
                ForEach(menuItems, id: \.destination.hashValue) { item in
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            currentSelection = item.destination
                        }
                    }) {
                        HStack(spacing: 15) {
                            // Icon
                            Image(systemName: item.icon)
                                .font(.system(size: 26, weight: .bold))
                                .frame(width: 35)
                                .foregroundColor(
                                    focusedItem == item.destination ? .black :
                                    currentSelection == item.destination ? CinemeltTheme.accent : .gray
                                )
                            
                            // Label
                            Text(item.label)
                                .font(CinemeltTheme.fontBody(24))
                                .fontWeight(currentSelection == item.destination ? .bold : .medium)
                                .foregroundColor(
                                    focusedItem == item.destination ? .black :
                                    currentSelection == item.destination ? CinemeltTheme.cream : .gray
                                )
                            
                            Spacer()
                            
                            // Active Indicator (Glowing Orb)
                            if currentSelection == item.destination {
                                Circle()
                                    .fill(CinemeltTheme.accent)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: CinemeltTheme.accent, radius: 6)
                                    .matchedGeometryEffect(id: "activeOrb", in: animationNamespace)
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        .background(
                            ZStack {
                                // Focused State (White Plate)
                                if focusedItem == item.destination {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(CinemeltTheme.accent)
                                        .shadow(color: CinemeltTheme.accent.opacity(0.6), radius: 12)
                                }
                                // Selected State (Subtle Glass)
                                else if currentSelection == item.destination {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white.opacity(0.08))
                                }
                            }
                        )
                    }
                    .buttonStyle(.card)
                    .focused($focusedItem, equals: item.destination)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // 3. Footer
            Text("v1.0")
                .font(CinemeltTheme.fontBody(14))
                .foregroundColor(.gray.opacity(0.5))
                .padding(.bottom, 40)
        }
        .frame(width: 300)
        // Make it a floating capsule, not a full edge bar
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
                .background(Color.black.opacity(0.4))
                .shadow(color: .black.opacity(0.5), radius: 30, x: 10, y: 0)
        )
        .padding(.vertical, 40) // Detach from top/bottom
        .padding(.leading, 40)  // Detach from left edge
        .zIndex(100)
    }
}
