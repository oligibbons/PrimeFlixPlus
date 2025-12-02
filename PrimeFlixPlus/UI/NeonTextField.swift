import SwiftUI

struct NeonTextField: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false
    var contentType: UITextContentType? = nil
    
    // We monitor focus internally to apply the glow
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(isFocused ? .cyan : .gray)
                .padding(.leading, 4)
            
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.15))
                
                // The Actual Input
                if isSecure {
                    SecureField("", text: $text)
                        .focused($isFocused)
                        .textContentType(contentType)
                        .padding(16)
                } else {
                    TextField("", text: $text)
                        .focused($isFocused)
                        .textContentType(contentType)
                        .padding(16)
                }
                
                // Neon Glow Border
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isFocused ? Color.cyan : Color.clear, lineWidth: 3)
                    .shadow(color: isFocused ? Color.cyan.opacity(0.8) : .clear, radius: 10, x: 0, y: 0)
            }
            .frame(height: 60)
            .scaleEffect(isFocused ? 1.02 : 1.0) // Subtle "pop" animation
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
        }
    }
}
