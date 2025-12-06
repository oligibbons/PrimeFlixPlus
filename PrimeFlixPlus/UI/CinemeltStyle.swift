import SwiftUI

/// The central Design System for "Cinemelt" v2.1 (Visual Refinement Update).
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
    
    // MARK: - Fonts
    static func fontTitle(_ size: CGFloat) -> Font {
        return .custom("Zain-Bold", size: size)
    }
    
    static func fontBody(_ size: CGFloat) -> Font {
        return .custom("Zain-Regular", size: size)
    }
}

// MARK: - Texture Generator
struct GrainOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                // Optimized grain count for performance
                for _ in 0..<Int(size.width * size.height / 500) {
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

// MARK: - Premium Loading Indicator (NEW)
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

// MARK: - Button Styles

struct CinemeltCardButtonView: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused: Bool
    
    var body: some View {
        configuration.label
            // Micro-Interaction: Bouncy scale on press
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.1 : 1.0))
            // Ambilight Glow
            .shadow(
                color: isFocused ? CinemeltTheme.accent.opacity(0.7) : .black.opacity(0.3),
                radius: isFocused ? 30 : 5,
                x: 0,
                y: isFocused ? 15 : 2
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.8 : 0), lineWidth: 2)
                    .blur(radius: isFocused ? 1 : 0)
            )
            // Animation Stack
            // 1. Focus: Smooth spring
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isFocused)
            // 2. Press: Rapid, tactile bounce (Pulse effect)
            .animation(.spring(response: 0.2, dampingFraction: 0.4), value: configuration.isPressed)
            .zIndex(isFocused ? 1 : 0)
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
