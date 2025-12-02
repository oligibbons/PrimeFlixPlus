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
        HStack(spacing: 50) {
            
            // Left: Branding & Instructions
            VStack(alignment: .leading, spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.1))
                        .frame(width: 150, height: 150)
                        .blur(radius: 20)
                    
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 100))
                        .foregroundColor(.cyan)
                }
                
                Text("Connect Provider")
                    .font(.custom("Exo2-Bold", size: 48)) // Custom Font
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Enter your Xtream Codes API details.\nCredentials are encrypted and stored locally.")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Cancel")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: 500)
            
            // Right: Form
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(2.0)
                        Text("Authenticating...")
                            .font(.headline)
                            .foregroundColor(.cyan)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 1. Server URL
                    neonInput(
                        title: "SERVER URL",
                        placeholder: "http://line.example.com",
                        text: $viewModel.serverUrl,
                        field: .url,
                        nextField: .username
                    )
                    
                    // 2. Username
                    neonInput(
                        title: "USERNAME",
                        placeholder: "User123",
                        text: $viewModel.username,
                        field: .username,
                        nextField: .password
                    )
                    
                    // 3. Password
                    neonInput(
                        title: "PASSWORD",
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
                        .font(.headline)
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
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.card)
                    .focused($focusedField, equals: .connectButton)
                    .disabled(viewModel.serverUrl.isEmpty || viewModel.username.isEmpty || viewModel.password.isEmpty)
                }
            }
            .padding(60)
            .background(Color(white: 0.1).blur(radius: 20)) // Fallback for material
            .cornerRadius(30)
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)
        }
        .padding(50)
        .background(
            ZStack {
                Color.black
                // Optional: Background Image here
            }
            .ignoresSafeArea()
        )
        .onAppear {
            viewModel.configure(repository: repository)
            // Fix for initial focus on tvOS 15
            // Only set focus if nothing is currently focused
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.focusedField == nil {
                    self.focusedField = .url
                }
            }
        }
    }
    
    // MARK: - Helper for Consistent Styling
    @ViewBuilder
    private func neonInput(title: String, placeholder: String, text: Binding<String>, field: Field, nextField: Field, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(focusedField == field ? .cyan : .gray)
                .padding(.leading, 4)
                .animation(.easeInOut, value: focusedField)
            
            if isSecure {
                SecureField(placeholder, text: text)
                    .focused($focusedField, equals: field)
                    .submitLabel(.next)
                    .onSubmit { focusedField = nextField }
                    .padding(20)
                    .background(Color(white: 0.15))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(focusedField == field ? Color.cyan : Color.clear, lineWidth: 3)
                            .shadow(color: focusedField == field ? .cyan.opacity(0.6) : .clear, radius: 15, x: 0, y: 0)
                    )
                    .scaleEffect(focusedField == field ? 1.02 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.4), value: focusedField)
            } else {
                TextField(placeholder, text: text)
                    .focused($focusedField, equals: field)
                    .submitLabel(.next)
                    .onSubmit { focusedField = nextField }
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
                    .padding(20)
                    .background(Color(white: 0.15))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(focusedField == field ? Color.cyan : Color.clear, lineWidth: 3)
                            .shadow(color: focusedField == field ? .cyan.opacity(0.6) : .clear, radius: 15, x: 0, y: 0)
                    )
                    .scaleEffect(focusedField == field ? 1.02 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.4), value: focusedField)
            }
        }
    }
}
