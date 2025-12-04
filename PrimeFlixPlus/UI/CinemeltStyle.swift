import SwiftUI

/// The central Design System for "Cinemelt" v2.0.
struct CinemeltTheme {
    
    // MARK: - Colors
    static let accent = Color(red: 255/255, green: 140/255, blue: 60/255) // Warm glowing amber
    static let accentDim = Color(red: 180/255, green: 90/255, blue: 40/255) // Darker amber
    static let cream = Color(red: 245/255, green: 240/255, blue: 230/255) // Soft off-white
    
    // Core Background Colors
    static let charcoal = Color(red: 30/255, green: 28/255, blue: 26/255)
    static let coffee = Color(red: 15/255, green: 12/255, blue: 10/255)
    
    // MARK: - Backward Compatibility (Fixes Build Errors)
    // These map the old naming convention to the new palette so other files compile.
    static let backgroundStart = charcoal
    static let backgroundEnd = coffee
    static let glassSurface = Color.white.opacity(0.1)
    
    // MARK: - Gradients & Backgrounds
    static var mainBackground: some View {
        ZStack {
            // Base layer
            LinearGradient(
                gradient: Gradient(colors: [charcoal, coffee]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Ambient Orbs
            GeometryReader { geo in
                Circle()
                    .fill(accent.opacity(0.15))
                    .blur(radius: 120)
                    .frame(width: geo.size.width * 0.6)
                    .position(x: 0, y: 0)
                
                Circle()
                    .fill(Color.black.opacity(0.8))
                    .blur(radius: 100)
                    .frame(width: geo.size.width * 0.5)
                    .position(x: geo.size.width, y: geo.size.height)
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Fonts
    static func fontTitle(_ size: CGFloat) -> Font {
        return .custom("Zain-Bold", size: size)
    }
    
    static func fontBody(_ size: CGFloat) -> Font {
        return .custom("Zain-Regular", size: size)
    }
}

// MARK: - View Modifiers

struct CinemeltGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            .cornerRadius(cornerRadius)
            .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

struct CinemeltTextGlow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: CinemeltTheme.accent.opacity(0.4), radius: 10, x: 0, y: 0)
    }
}

// MARK: - Button Styles

// A wrapper view to handle Focus State cleanly within a ButtonStyle
struct CinemeltCardButtonView: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused: Bool
    
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.1 : 1.0))
            // Ambilight Glow
            .shadow(
                color: isFocused ? CinemeltTheme.accent.opacity(0.6) : .black.opacity(0.3),
                radius: isFocused ? 30 : 5,
                x: 0,
                y: isFocused ? 15 : 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(isFocused ? 0.5 : 0), lineWidth: 2)
                    .blur(radius: 1)
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.55), value: isFocused)
    }
}

struct CinemeltCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CinemeltCardButtonView(configuration: configuration)
    }
}

extension View {
    func cinemeltGlass(radius: CGFloat = 20) -> some View {
        self.modifier(CinemeltGlassModifier(cornerRadius: radius))
    }
    
    func cinemeltGlow() -> some View {
        self.modifier(CinemeltTextGlow())
    }
    
    func cinemeltTitle() -> some View {
        self.font(CinemeltTheme.fontTitle(40)).foregroundColor(CinemeltTheme.cream)
    }
    
    func cinemeltBody() -> some View {
        self.font(CinemeltTheme.fontBody(28)).foregroundColor(CinemeltTheme.cream.opacity(0.8))
    }
}
