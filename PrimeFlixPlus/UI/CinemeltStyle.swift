import SwiftUI

/// The central Design System for "Cinemelt".
/// Defines the cosy, warm, glassmorphic visual language.
struct CinemeltTheme {
    
    // MARK: - Colors
    // Derived from the "Cinemelt Icon.jpg" warm palette
    static let accent = Color(red: 255/255, green: 140/255, blue: 60/255) // Warm glowing amber
    static let backgroundStart = Color(red: 30/255, green: 28/255, blue: 26/255) // Deep warm charcoal
    static let backgroundEnd = Color(red: 10/255, green: 8/255, blue: 6/255) // Near black coffee
    static let cream = Color(red: 245/255, green: 240/255, blue: 230/255) // Soft off-white text
    static let glassSurface = Color.white.opacity(0.1)
    
    // MARK: - Gradients
    static var mainBackground: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [backgroundStart, backgroundEnd]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Fonts
    // Uses the uploaded Zain-Bold and Zain-Regular
    static func fontTitle(_ size: CGFloat) -> Font {
        return .custom("Zain-Bold", size: size)
    }
    
    static func fontBody(_ size: CGFloat) -> Font {
        return .custom("Zain-Regular", size: size)
    }
}

// MARK: - View Modifiers

struct CinemeltGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial) // Native Apple TV blur
            .background(Color.white.opacity(0.05)) // Slight tint
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct CinemeltCardStyle: ButtonStyle {
    @State private var isFocused: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .shadow(color: isFocused ? CinemeltTheme.accent.opacity(0.5) : .black.opacity(0.3), radius: isFocused ? 20 : 5)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
            .onChange(of: configuration.isPressed) { _ in
                // tvOS buttons handle focus state differently, but this captures press
            }
    }
}

extension View {
    func cinemeltGlass() -> some View {
        self.modifier(CinemeltGlassModifier())
    }
    
    func cinemeltTitle() -> some View {
        self.font(CinemeltTheme.fontTitle(40)).foregroundColor(CinemeltTheme.cream)
    }
    
    func cinemeltBody() -> some View {
        self.font(CinemeltTheme.fontBody(28)).foregroundColor(CinemeltTheme.cream.opacity(0.8))
    }
}
