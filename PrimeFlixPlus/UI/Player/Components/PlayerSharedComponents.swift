import SwiftUI
import TVVLCKit

// MARK: - Time Formatting Helper
struct PlayerTimeFormatter {
    static func string(from seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite { return "--:--" }
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - UI Components

struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(CinemeltTheme.fontBody(16))
            .fontWeight(.bold)
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CinemeltTheme.accent)
            .cornerRadius(4)
    }
}

struct HintItem: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(CinemeltTheme.fontBody(18))
        }
        .foregroundColor(.white.opacity(0.5))
    }
}

// MARK: - Shape Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - VLC Bridge
struct VLCVideoSurface: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerViewModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        viewModel.assignView(view)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Siri Remote Swipe Handler
struct SiriRemoteSwipeHandler: UIViewRepresentable {
    // Returns X (Horizontal) and Y (Vertical) translation
    var onPan: (CGFloat, CGFloat) -> Void
    var onEnd: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(panGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPan: onPan, onEnd: onEnd)
    }
    
    class Coordinator: NSObject {
        var onPan: (CGFloat, CGFloat) -> Void
        var onEnd: () -> Void
        
        init(onPan: @escaping (CGFloat, CGFloat) -> Void, onEnd: @escaping () -> Void) {
            self.onPan = onPan
            self.onEnd = onEnd
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .changed {
                let translation = gesture.translation(in: gesture.view)
                onPan(translation.x, translation.y)
            } else if gesture.state == .ended || gesture.state == .cancelled {
                onEnd()
            }
        }
    }
}
