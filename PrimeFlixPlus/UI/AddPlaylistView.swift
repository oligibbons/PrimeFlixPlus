import SwiftUI

struct AddPlaylistView: View {
    @StateObject private var viewModel = AddPlaylistViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlaylistAdded: () -> Void
    var onBack: () -> Void
    
    // Define focusable fields
    enum Field: Hashable {
        case url
        case username
        case password
        case connectButton
    }
    
    // Bind focus state to the view
    @FocusState private var focusedField: Field?
    
    var body: some View {
        HStack(spacing: 80) {
            
            // Left: Branding & Instructions (Cinemelt Style)
            VStack(alignment: .leading, spacing: 30) {
                
                // Icon / Logo Placeholder
                Image(systemName: "tv.badge.wifi.fill")
                    .font(.system(size: 100))
                    .foregroundColor(CinemeltTheme.accent)
                    .shadow(color: CinemeltTheme.accent.opacity(0.5), radius: 20, x: 0, y: 10)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect Provider")
                        .font(CinemeltTheme.fontTitle(60))
                        .foregroundColor(CinemeltTheme.cream)
                    
                    Text("Enter your Xtream Codes API details.\nCredentials are encrypted and stored locally.")
                        .font(CinemeltTheme.fontBody(28))
                        .foregroundColor(.gray)
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Cancel")
                    }
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(CinemeltTheme.cream.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 550)
            
            // Right: Glassmorphic Form
            VStack(spacing: 30) {
                if viewModel.isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .tint(CinemeltTheme.accent)
                            .scaleEffect(2.0)
                        Text("Authenticating...")
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(CinemeltTheme.accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 1. Server URL
                    glassInput(
                        title: "Server URL",
                        placeholder: "http://line.example.com",
                        text: $viewModel.serverUrl,
                        field: .url,
                        nextField: .username
                    )
                    
                    // 2. Username
                    glassInput(
                        title: "Username",
                        placeholder: "User123",
                        text: $viewModel.username,
                        field: .username,
                        nextField: .password
                    )
                    
                    // 3. Password
                    glassInput(
                        title: "Password",
                        placeholder: "••••••",
                        text: $viewModel.password,
                        field: .password,
                        nextField: .connectButton,
                        isSecure: true
                    )
                    
                    if let error = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.red)
                        .padding(.top, 10)
                        .transition(.opacity)
                    }
                    
                    Spacer().frame(height: 10)
                    
                    // 4. Connect Button
                    Button(action: {
                        Task {
                            await viewModel.addAccount()
                            if viewModel.isSuccess {
                                onPlaylistAdded()
                            }
                        }
                    }) {
                        Text("Connect Account")
                            .font(CinemeltTheme.fontTitle(24))
                            .foregroundColor(.black) // Black text on Amber button
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(CinemeltTheme.accent)
                            )
                    }
                    .buttonStyle(.card)
                    .focused($focusedField, equals: .connectButton)
                    .disabled(viewModel.serverUrl.isEmpty || viewModel.username.isEmpty || viewModel.password.isEmpty)
                    .opacity(viewModel.serverUrl.isEmpty ? 0.5 : 1.0)
                }
            }
            .padding(60)
            .background(.ultraThinMaterial) // Apple TV Glass
            .background(Color.white.opacity(0.05)) // Subtle tint
            .cornerRadius(40)
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
        }
        .padding(60)
        .background(
            CinemeltTheme.mainBackground.ignoresSafeArea()
        )
        .onAppear {
            viewModel.configure(repository: repository)
            // Fix for initial focus on tvOS
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.focusedField == nil {
                    self.focusedField = .url
                }
            }
        }
    }
    
    // MARK: - Helper for Consistent Styling (Glassmorphic)
    @ViewBuilder
    private func glassInput(title: String, placeholder: String, text: Binding<String>, field: Field, nextField: Field, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(CinemeltTheme.fontTitle(20))
                .foregroundColor(focusedField == field ? CinemeltTheme.accent : .gray)
                .padding(.leading, 4)
                .animation(.easeInOut, value: focusedField)
            
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                }
            }
            .font(CinemeltTheme.fontBody(24))
            .focused($focusedField, equals: field)
            .submitLabel(.next)
            .onSubmit { focusedField = nextField }
            .padding(20)
            .background(Color.black.opacity(0.3)) // Darker inset for fields
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focusedField == field ? CinemeltTheme.accent : Color.white.opacity(0.1), lineWidth: 2)
            )
            .scaleEffect(focusedField == field ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: focusedField)
        }
    }
}
