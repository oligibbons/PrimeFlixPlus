import SwiftUI

struct SidebarView: View {
    @Binding var currentSelection: NavigationDestination
    @Namespace private var animationNamespace
    @FocusState private var focusedItem: NavigationDestination?
    
    // Width Constants
    private let collapsedWidth: CGFloat = 100
    private let expandedWidth: CGFloat = 400
    
    // Determine if the sidebar is currently active (expanded)
    private var isExpanded: Bool {
        return focusedItem != nil
    }
    
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
        ZStack(alignment: .leading) {
            
            // 1. Glassmorphic Background
            // We use .ultraThinMaterial to blur what's behind it.
            // The overlay adds a slight tint without blocking the view.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            CinemeltTheme.charcoal.opacity(0.5), // Semi-transparent tint
                            CinemeltTheme.coffee.opacity(0.3)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                
                // 2. Logo Area
                VStack {
                    Image("CinemeltLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        // Scale logic: nice and small when collapsed, larger when open
                        .frame(width: isExpanded ? 140 : 50, height: isExpanded ? 80 : 50)
                        .shadow(color: CinemeltTheme.accent.opacity(0.4), radius: 20, x: 0, y: 10)
                }
                .frame(maxWidth: .infinity) // Centers the logo horizontally in the current width
                .padding(.top, 50)
                .padding(.bottom, 40)
                
                // 3. Navigation Items (FIXED: Wrapped in ScrollView and focusedSection)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(menuItems, id: \.destination.hashValue) { item in
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    currentSelection = item.destination
                                }
                            }) {
                                HStack(spacing: 25) { // Increased spacing for cleaner text separation
                                    // Icon Container (Fixed width ensures alignment)
                                    ZStack {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundColor(
                                                focusedItem == item.destination ? .black :
                                                currentSelection == item.destination ? CinemeltTheme.accent : .white.opacity(0.7)
                                            )
                                    }
                                    .frame(width: 30, height: 30)
                                    
                                    // Label (Visible only when expanded)
                                    if isExpanded {
                                        Text(item.label)
                                            .font(CinemeltTheme.fontBody(26))
                                            .fontWeight(currentSelection == item.destination ? .bold : .medium)
                                            .foregroundColor(
                                                focusedItem == item.destination ? .black :
                                                currentSelection == item.destination ? CinemeltTheme.cream : .white.opacity(0.7)
                                            )
                                            .lineLimit(1)
                                            .transition(.opacity)
                                    }
                                    
                                    Spacer()
                                    
                                    // Active Indicator (Dot)
                                    if currentSelection == item.destination && isExpanded {
                                        Circle()
                                            .fill(focusedItem == item.destination ? .black : CinemeltTheme.accent)
                                            .frame(width: 8, height: 8)
                                            .matchedGeometryEffect(id: "activeIndicator", in: animationNamespace)
                                    }
                                }
                                // Inner padding of the button itself
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(SidebarButtonStyle(isSelected: currentSelection == item.destination))
                            .focused($focusedItem, equals: item.destination)
                        }
                    }
                    .padding(.horizontal, 16) // Padding around the button stack
                    // FIX: Explicitly set focus boundary for sidebar list
                    .focusSection()
                }
                
                Spacer()
                
                // 4. Footer
                if isExpanded {
                    VStack(spacing: 5) {
                        Text("PrimeFlix")
                            .font(CinemeltTheme.fontBody(16))
                            .foregroundColor(CinemeltTheme.cream)
                        Text("v1.2.0")
                            .font(CinemeltTheme.fontBody(14))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 40)
                    .transition(.opacity)
                }
            }
        }
        // Animating width based on focus state
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
        .zIndex(100)
    }
}

struct SidebarButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isFocused) var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                ZStack {
                    if isFocused {
                        // Focused State: Accent Color with Glow
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(CinemeltTheme.accent)
                            .shadow(color: CinemeltTheme.accent.opacity(0.5), radius: 15, x: 0, y: 5)
                    } else if isSelected {
                        // Selected (Active) but not focused: Glassy highlight
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    }
                }
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
    }
}
