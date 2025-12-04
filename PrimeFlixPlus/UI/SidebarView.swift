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
        VStack(alignment: .leading, spacing: 30) {
            
            // Logo Area
            VStack(spacing: 10) {
                Image("CinemeltLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)
                    .shadow(color: CinemeltTheme.accent.opacity(0.5), radius: 15, x: 0, y: 5)
                
                // Use image if available, otherwise text fallback
                if UIImage(named: "CinemeltLogo") == nil {
                    Text("Cinemelt")
                        .font(.custom("Zain-Bold", size: 30))
                        .foregroundColor(CinemeltTheme.cream)
                        .tracking(2)
                }
            }
            .padding(.bottom, 40)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .center)
            
            // Navigation Items
            ForEach(menuItems, id: \.destination.hashValue) { item in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentSelection = item.destination
                    }
                }) {
                    HStack(spacing: 15) {
                        Image(systemName: item.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 35) // Fixed width icon for alignment
                        
                        Text(item.label)
                            .font(CinemeltTheme.fontBody(24))
                            .fontWeight(.semibold)
                        
                        Spacer() // Forces text to left align comfortably
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                }
                .buttonStyle(.card)
                .focused($focusedItem, equals: item.destination)
                .background(
                    ZStack {
                        if currentSelection == item.destination {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                                .matchedGeometryEffect(id: "activeTab", in: animationNamespace)
                        }
                    }
                )
                .foregroundColor(
                    focusedItem == item.destination ? .black :
                    currentSelection == item.destination ? CinemeltTheme.accent : .gray
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
    }
}
