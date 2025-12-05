import SwiftUI

struct AddPlaylistView: View, Equatable {
    // MARK: - Equatable (Stops Parent Redraws from killing Keyboard)
    static func == (lhs: AddPlaylistView, rhs: AddPlaylistView) -> Bool {
        return true // This view is static once presented; ignore external updates
    }
    
    @StateObject private var viewModel = AddPlaylistViewModel()
    
    // Dependency Injection (Not Observed Object) guarantees isolation
    let repository: PrimeFlixRepository
    
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
                        // --- INPUT: Server URL ---
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Server URL")
                                .font(CinemeltTheme.fontBody(20))
                                .fontWeight(.bold)
                                .foregroundColor(focusedField == .url ? CinemeltTheme.accent : .gray)
                                .padding(.leading, 4)
                            
                            TextField("http://provider.dns", text: $viewModel.serverUrl)
                                .font(CinemeltTheme.fontBody(26))
                                .focused($focusedField, equals: .url)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .username }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            focusedField == .url ? CinemeltTheme.accent : Color.white.opacity(0.1),
                                            lineWidth: focusedField == .url ? 2 : 1
                                        )
                                )
                                .shadow(
                                    color: focusedField == .url ? CinemeltTheme.accent.opacity(0.4) : .clear,
                                    radius: 15, x: 0, y: 0
                                )
                                .scaleEffect(focusedField == .url ? 1.02 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: focusedField)
                        }
                        
                        // --- INPUT: Username ---
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Username")
                                .font(CinemeltTheme.fontBody(20))
                                .fontWeight(.bold)
                                .foregroundColor(focusedField == .username ? CinemeltTheme.accent : .gray)
                                .padding(.leading, 4)
                            
                            TextField("User123", text: $viewModel.username)
                                .font(CinemeltTheme.fontBody(26))
                                .focused($focusedField, equals: .username)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            focusedField == .username ? CinemeltTheme.accent : Color.white.opacity(0.1),
                                            lineWidth: focusedField == .username ? 2 : 1
                                        )
                                )
                                .shadow(
                                    color: focusedField == .username ? CinemeltTheme.accent.opacity(0.4) : .clear,
                                    radius: 15, x: 0, y: 0
                                )
                                .scaleEffect(focusedField == .username ? 1.02 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: focusedField)
                        }
                        
                        // --- INPUT: Password ---
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Password")
                                .font(CinemeltTheme.fontBody(20))
                                .fontWeight(.bold)
                                .foregroundColor(focusedField == .password ? CinemeltTheme.accent : .gray)
                                .padding(.leading, 4)
                            
                            SecureField("••••••", text: $viewModel.password)
                                .font(CinemeltTheme.fontBody(26))
                                .focused($focusedField, equals: .password)
                                .submitLabel(.done)
                                .onSubmit { focusedField = .connectButton }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            focusedField == .password ? CinemeltTheme.accent : Color.white.opacity(0.1),
                                            lineWidth: focusedField == .password ? 2 : 1
                                        )
                                )
                                .shadow(
                                    color: focusedField == .password ? CinemeltTheme.accent.opacity(0.4) : .clear,
                                    radius: 15, x: 0, y: 0
                                )
                                .scaleEffect(focusedField == .password ? 1.02 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: focusedField)
                        }
                        
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
            // Manual injection of repository
            viewModel.configure(repository: repository)
            
            // Only auto-focus if we haven't started typing yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.focusedField == nil && viewModel.serverUrl.isEmpty {
                    self.focusedField = .url
                }
            }
        }
    }
}
