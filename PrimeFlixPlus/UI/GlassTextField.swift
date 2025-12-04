import SwiftUI

struct GlassTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var nextFocus: () -> Void
    
    // Internal focus state (visuals only)
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(CinemeltTheme.fontBody(20))
                .fontWeight(.bold)
                .foregroundColor(isFocused ? CinemeltTheme.accent : .gray)
                .padding(.leading, 4)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
            
            ZStack {
                // Background Plate
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                
                // Input
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(CinemeltTheme.fontBody(26))
                        .focused($isFocused)
                        .submitLabel(.next)
                        .onSubmit { nextFocus() }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .foregroundColor(.white)
                } else {
                    TextField(placeholder, text: $text)
                        .font(CinemeltTheme.fontBody(26))
                        .focused($isFocused)
                        .submitLabel(.next)
                        .onSubmit { nextFocus() }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .foregroundColor(.white)
                }
            }
            // The "Neon Border" Effect
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isFocused ? CinemeltTheme.accent : Color.white.opacity(0.1),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            // The "Bloom" Effect
            .shadow(
                color: isFocused ? CinemeltTheme.accent.opacity(0.4) : .clear,
                radius: 15, x: 0, y: 0
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
        }
    }
}
