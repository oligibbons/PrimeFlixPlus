import SwiftUI

/// A reusable Neon-styled text field for tvOS.
/// Note: For complex forms with specific tab ordering, use the inline builder pattern (like in AddPlaylistView).
/// This component is best for standalone inputs like Search.
struct NeonTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var contentType: UITextContentType? = nil
    var onSubmit: (() -> Void)? = nil
    
    // Internal focus state for self-managed instances
    @FocusState private var internalFocus: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(internalFocus ? .cyan : .gray)
                .padding(.leading, 4)
            
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.15))
                
                // The Actual Input
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .focused($internalFocus)
                        .textContentType(contentType)
                        .submitLabel(.done)
                        .onSubmit { onSubmit?() }
                        .padding(16)
                } else {
                    TextField(placeholder, text: $text)
                        .focused($internalFocus)
                        .textContentType(contentType)
                        .submitLabel(.done)
                        .onSubmit { onSubmit?() }
                        .padding(16)
                }
                
                // Neon Glow Border
                RoundedRectangle(cornerRadius: 12)
                    .stroke(internalFocus ? Color.cyan : Color.clear, lineWidth: 3)
                    .shadow(color: internalFocus ? Color.cyan.opacity(0.8) : .clear, radius: 10, x: 0, y: 0)
            }
            .frame(height: 60)
            .scaleEffect(internalFocus ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: internalFocus)
        }
    }
}
