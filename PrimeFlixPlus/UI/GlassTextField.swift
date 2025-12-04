import SwiftUI

/// A reusable Glassmorphic text field for tvOS.
/// Replaces the old "NeonTextField".
struct GlassTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var contentType: UITextContentType? = nil
    var onSubmit: (() -> Void)? = nil
    
    // Internal focus state for self-managed instances
    @FocusState private var internalFocus: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(CinemeltTheme.fontBody(18))
                .fontWeight(.bold)
                .foregroundColor(internalFocus ? CinemeltTheme.accent : .gray)
                .padding(.leading, 4)
                .animation(.easeInOut, value: internalFocus)
            
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.15))
                    .blur(radius: internalFocus ? 0 : 0) // Crisp when focused
                
                // The Actual Input
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(CinemeltTheme.fontBody(24))
                        .focused($internalFocus)
                        .textContentType(contentType)
                        .submitLabel(.done)
                        .onSubmit { onSubmit?() }
                        .padding(20)
                } else {
                    TextField(placeholder, text: $text)
                        .font(CinemeltTheme.fontBody(24))
                        .focused($internalFocus)
                        .textContentType(contentType)
                        .submitLabel(.done)
                        .onSubmit { onSubmit?() }
                        .padding(20)
                }
                
                // Active Border (Warm Amber instead of Neon Cyan)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(internalFocus ? CinemeltTheme.accent : Color.white.opacity(0.1), lineWidth: 3)
            }
            .frame(height: 70)
            // Parallax Scale Effect
            .scaleEffect(internalFocus ? 1.02 : 1.0)
            .shadow(color: internalFocus ? CinemeltTheme.accent.opacity(0.4) : .clear, radius: 15, x: 0, y: 5)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: internalFocus)
        }
    }
}
