import SwiftUI

struct SidebarView: View {
    @Binding var currentSelection: NavigationDestination
    @Namespace private var animationNamespace
    @FocusState private var focusedItem: NavigationDestination?
    
    // Define the menu items
    let menuItems: [(destination: NavigationDestination, icon: String, label: String)] = [
        (.home, "house.fill", "Home"),
        (.continueWatching, "play.tv.fill", "Watching"),
        (.favorites, "heart.fill", "Favorites"),
        (.search, "magnifyingglass", "Search"),
        (.settings, "gearshape.fill", "Settings"),
        (.addPlaylist, "person.badge.plus", "Profiles")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 1. Logo
            VStack {
                Image("CinemeltLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 180, height: 100)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
            .padding(.bottom, 40)
            
            // 2. Navigation Items
            VStack(spacing: 20) {
                ForEach(menuItems, id: \.destination.hashValue) { item in
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            currentSelection = item.destination
                        }
                    }) {
                        HStack(spacing: 20) {
                            // Icon
                            Image(systemName: item.icon)
                                .font(.system(size: 24, weight: .semibold))
                                .frame(width: 30)
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
                            
                            // Active Indicator
                            if currentSelection == item.destination {
                                Capsule()
                                    .fill(CinemeltTheme.accent)
                                    .frame(width: 4, height: 20)
                                    .matchedGeometryEffect(id: "activeIndicator", in: animationNamespace)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            ZStack {
                                if focusedItem == item.destination {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(CinemeltTheme.accent)
                                        .shadow(color: CinemeltTheme.accent.opacity(0.5), radius: 15)
                                } else if currentSelection == item.destination {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                }
                            }
                        )
                    }
                    .buttonStyle(.card)
                    .focused($focusedItem, equals: item.destination)
                }
            }
            .padding(.horizontal, 16)
            // MARK: - CRITICAL FIX
            // This creates a "Focus Group". When navigating out of this group (Right),
            // tvOS will automatically find the best target in the next group (Content),
            // regardless of specific vertical alignment.
            .focusSection()
            
            Spacer()
            
            // 3. Footer
            Text("v1.0")
                .font(CinemeltTheme.fontBody(12))
                .foregroundColor(.gray.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 30)
        }
        .frame(width: 280)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
        .zIndex(100)
    }
}
