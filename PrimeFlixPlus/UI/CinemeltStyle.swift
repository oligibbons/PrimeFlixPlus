import SwiftUI

/// The central Design System for "Cinemelt" v2.1 (Visual Refinement Update).
/// Refactored for tvOS 15.4+ with proper Focus Engines and Overscan protection.
struct CinemeltTheme {
    
    // MARK: - Colors
    static let accent = Color(red: 255/255, green: 140/255, blue: 60/255) // Warm glowing amber
    static let accentDim = Color(red: 180/255, green: 90/255, blue: 40/255) // Deep amber
    static let cream = Color(red: 245/255, green: 240/255, blue: 230/255) // Soft off-white
    
    // Deep Backgrounds
    static let charcoal = Color(red: 20/255, green: 18/255, blue: 16/255)
    static let coffee = Color(red: 10/255, green: 8/255, blue: 6/255)
    static let glassSurface = Color.white.opacity(0.08)
    
    // Backward Compatibility
    static let backgroundStart = charcoal
    static let backgroundEnd = coffee
    
    // MARK: - Atmospheric Background
    static var mainBackground: some View {
        ZStack {
            // 1. Deep Base
            LinearGradient(
                gradient: Gradient(colors: [charcoal, coffee]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // 2. The "Studio Light"
            GeometryReader { geo in
                // Top Left Rim Light (White/Blueish)
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .blur(radius: 200)
                    .frame(width: geo.size.width * 0.8)
                    .position(x: 0, y: -100)
                
                // Bottom Right Warmth
                Circle()
                    .fill(accent.opacity(0.15))
                    .blur(radius: 150)
                    .frame(width: geo.size.width * 0.6)
                    .position(x: geo.size.width, y: geo.size.height)
            }
            
            // 3. Texture
            GrainOverlay()
                .opacity(0.04)
                .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Fonts (tvOS Optimized)
    
    /// Returns a title font. Automatically upgrades small sizes to tvOS standards (48pt+ recommended).
    static func fontTitle(_ size: CGFloat) -> Font {
        // Rule of 10ft: If requested size is too small for a title, bump it up.
        let effectiveSize = size < 30 ? 38 : size
        return .custom("Zain-Bold", size: effectiveSize)
    }
    
    /// Returns a body font. Enforces minimum readability (26pt+ recommended).
    static func fontBody(_ size: CGFloat) -> Font {
        // Rule of 10ft: Body text below 26pt is unreadable on many TVs.
        let effectiveSize = size < 20 ? 26 : size
        return .custom("Zain-Regular", size: effectiveSize)
    }
    
    // MARK: - Layout Constants
    struct Layout {
        // Critical: Apple TV Safe Area margins are huge (90pt standard).
        // Using less than this risks content being cut off on older TVs.
        static let margin: CGFloat = 90
        static let verticalSpacing: CGFloat = 60
        static let gutter: CGFloat = 40
        
        // Standardized Card Sizes for Grids
        static let posterWidth: CGFloat = 250
        static let posterHeight: CGFloat = 375
    }
}

// MARK: - Texture Generator
struct GrainOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                // Optimized grain count for performance
                // Reduced count slightly to ensure 60fps on older 4K boxes
                for _ in 0..<Int(size.width * size.height / 600) {
                    let x = Double.random(in: 0...size.width)
                    let y = Double.random(in: 0...size.height)
                    let opacity = Double.random(in: 0...0.5)
                    let rect = CGRect(x: x, y: y, width: 1.5, height: 1.5)
                    context.fill(Path(rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Premium Loading Indicator
struct CinemeltLoadingIndicator: View {
    @State private var isAnimating: Bool = false
    
    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 8)
                .frame(width: 80, height: 80)
            
            // Spinner
            Circle()
                .trim(from: 0, to: 0.6)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [CinemeltTheme.accent, CinemeltTheme.accentDim]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 80, height: 80)
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(
                    Animation.linear(duration: 1.0)
                        .repeatForever(autoreverses: false),
                    value: isAnimating
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - View Modifiers

struct CinemeltGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 1)
            )
    }
}

struct CinemeltTextGlow: ViewModifier {
    func body(content: Content) -> some View {
        // Subtle glow for emphasis
        content
            .shadow(color: CinemeltTheme.accent.opacity(0.3), radius: 8, x: 0, y: 0)
    }
}

// MARK: - Button Styles (UPDATED: Parallax Lift)

struct CinemeltCardButtonView: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused: Bool
    
    var body: some View {
        configuration.label
            // 1. The "Lift" Effect (Critical for tvOS Feel)
            // Instead of just scaling, we move it UP (-10 y) to simulate floating.
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.15 : 1.0))
            .offset(y: isFocused ? -10 : 0)
            
            // 2. Ambilight Glow (Enhanced for Focus)
            .shadow(
                color: isFocused ? CinemeltTheme.accent.opacity(0.6) : .black.opacity(0.3),
                radius: isFocused ? 30 : 5,
                x: 0,
                y: isFocused ? 20 : 2
            )
            
            // 3. Background Plate
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear) // Transparent hit target
            )
            
            // 4. Focus Border
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.8 : 0), lineWidth: 3)
                    .blur(radius: isFocused ? 1 : 0)
            )
            
            // Animation Stack
            // Focus: Springy and responsive
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isFocused)
            // Press: Quick feedback
            .animation(.spring(response: 0.2, dampingFraction: 0.4), value: configuration.isPressed)
            .zIndex(isFocused ? 1 : 0)
    }
}

struct CinemeltCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CinemeltCardButtonView(configuration: configuration)
    }
}

// MARK: - Usage Extensions

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
    
    // NEW: Safe Area Helper
    // Use this on your root VStacks/ScrollViews to ensure they aren't cut off by the TV bezel
    func standardSafePadding() -> some View {
        self.padding(.horizontal, CinemeltTheme.Layout.margin)
            .padding(.vertical, 60)
    }
}
