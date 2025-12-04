import SwiftUI

struct AddPlaylistView: View {
    @StateObject private var viewModel = AddPlaylistViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlaylistAdded: () -> Void
    var onBack: () -> Void
    
    // Define focusable fields
    enum Field: Hashable {
        case url, username, password, connectButton, backButton
    }
    
    @FocusState private var focusedField: Field?
    
    var body: some View {
        ZStack {
            // 1. Cinematic Background
            CinemeltTheme.mainBackground
            
            // 2. Atmospheric Background Icon
            GeometryReader { geo in
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 600))
                    .foregroundColor(CinemeltTheme.accent.opacity(0.05))
                    .position(x: geo.size.width * 0.8, y: geo.size.height * 0.5)
                    .blur(radius: 50)
            }
            
            // 3. The "Glass Monolith" Form
            HStack(spacing: 0) {
                
                // Left: Info & Branding
                VStack(alignment: .leading, spacing: 30) {
                    Button(action: onBack) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.left")
                            Text("Cancel")
                        }
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(CinemeltTheme.cream.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .focused($focusedField, equals: .backButton)
                    .padding(.bottom, 20)
                    
                    Text("New Profile")
                        .font(CinemeltTheme.fontTitle(60))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                    
                    Text("Enter your provider details securely.\nPrimeFlix supports Xtream Codes API.")
                        .font(CinemeltTheme.fontBody(26))
                        .foregroundColor(CinemeltTheme.cream.opacity(0.7))
                        .lineSpacing(8)
                    
                    Spacer()
                    
                    // Security Badge
                    HStack(spacing: 15) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(CinemeltTheme.accent)
                        Text("Credentials are encrypted locally on Apple TV.")
                            .font(CinemeltTheme.fontBody(18))
                            .foregroundColor(.gray)
                    }
                }
                .padding(60)
                .frame(width: 600)
                
                // Divider
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 1)
                    .padding(.vertical, 60)
                
                // Right: Input Fields
                VStack(spacing: 35) {
                    if viewModel.isLoading {
                        VStack(spacing: 30) {
                            ProgressView()
                                .tint(CinemeltTheme.accent)
                                .scaleEffect(2.5)
                            Text("Authenticating...")
                                .font(CinemeltTheme.fontBody(28))
                                .foregroundColor(CinemeltTheme.accent)
                                .cinemeltGlow()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Inputs
                        GlassTextField(
                            title: "Server URL",
                            placeholder: "http://provider.dns",
                            text: $viewModel.serverUrl,
                            nextFocus: { focusedField = .username }
                        )
                        .focused($focusedField, equals: .url)
                        
                        GlassTextField(
                            title: "Username",
                            placeholder: "User123",
                            text: $viewModel.username,
                            nextFocus: { focusedField = .password }
                        )
                        .focused($focusedField, equals: .username)
                        
                        GlassTextField(
                            title: "Password",
                            placeholder: "••••••",
                            text: $viewModel.password,
                            isSecure: true,
                            nextFocus: { focusedField = .connectButton }
                        )
                        .focused($focusedField, equals: .password)
                        
                        // Error State
                        if let error = viewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(error)
                            }
                            .font(CinemeltTheme.fontBody(22))
                            .foregroundColor(.red)
                            .padding(.top, 10)
                            .transition(.opacity)
                        }
                        
                        Spacer()
                        
                        // Action Button
                        Button(action: {
                            Task {
                                await viewModel.addAccount()
                                if viewModel.isSuccess { onPlaylistAdded() }
                            }
                        }) {
                            HStack {
                                Text("Connect Account")
                                Image(systemName: "arrow.right")
                            }
                            .font(CinemeltTheme.fontTitle(28))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(CinemeltTheme.accent)
                            .cornerRadius(16)
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        .focused($focusedField, equals: .connectButton)
                        .disabled(viewModel.serverUrl.isEmpty || viewModel.username.isEmpty || viewModel.password.isEmpty)
                        .opacity(viewModel.serverUrl.isEmpty ? 0.5 : 1.0)
                    }
                }
                .padding(60)
            }
            .frame(maxWidth: 1300, maxHeight: 700)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.4))
            .cornerRadius(40)
            .overlay(
                RoundedRectangle(cornerRadius: 40)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 50, x: 0, y: 20)
        }
        .onAppear {
            viewModel.configure(repository: repository)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.focusedField == nil { self.focusedField = .url }
            }
        }
    }
}
