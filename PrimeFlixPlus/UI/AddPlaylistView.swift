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
    
    @FocusState private var focusedField: Field?
    @State private var hasAppeared = false // Safety Flag
    
    var body: some View {
        HStack(spacing: 50) {
            
            // Left: Branding & Instructions
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 100))
                    .foregroundColor(.cyan)
                
                Text("Connect Xtream Codes")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Enter your IPTV provider details.\nYour credentials are saved locally.")
                    .foregroundColor(.gray)
                
                Spacer()
                
                Button("Cancel", action: onBack)
            }
            .frame(width: 400)
            
            // Right: Form
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    ProgressView("Verifying Credentials...")
                        .scaleEffect(1.5)
                } else {
                    // 1. Server URL
                    neonInput(
                        title: "SERVER URL",
                        text: $viewModel.serverUrl,
                        field: .url,
                        nextField: .username
                    )
                    
                    // 2. Username
                    neonInput(
                        title: "USERNAME",
                        text: $viewModel.username,
                        field: .username,
                        nextField: .password
                    )
                    
                    // 3. Password
                    neonInput(
                        title: "PASSWORD",
                        text: $viewModel.password,
                        field: .password,
                        nextField: .connectButton,
                        isSecure: true
                    )
                    
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .fontWeight(.semibold)
                    }
                    
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
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.card)
                    .focused($focusedField, equals: .connectButton)
                    .padding(.top, 10)
                }
            }
            .padding(50)
            .background(Color(white: 0.1))
            .cornerRadius(20)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            viewModel.configure(repository: repository)
            
            // CRITICAL FIX: Only force focus ONCE.
            // If you are fast and click before 0.5s, this block won't run or won't reset active focus.
            if !hasAppeared {
                hasAppeared = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Only reset focus if NOTHING is focused
                    if self.focusedField == nil {
                        self.focusedField = .url
                    }
                }
            }
        }
    }
    
    // MARK: - Helper for Consistent Styling
    @ViewBuilder
    private func neonInput(title: String, text: Binding<String>, field: Field, nextField: Field, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(focusedField == field ? .cyan : .gray)
                .padding(.leading, 4)
            
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.15))
                
                // Input Field
                if isSecure {
                    SecureField(title, text: text)
                        .focused($focusedField, equals: field)
                        .submitLabel(.next)
                        .onSubmit { focusedField = nextField }
                        .padding(16)
                } else {
                    TextField(title, text: text)
                        .focused($focusedField, equals: field)
                        .submitLabel(.next)
                        .onSubmit { focusedField = nextField }
                        .padding(16)
                        .keyboardType(.URL)
                }
                
                // Neon Glow Border
                if focusedField == field {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.cyan, lineWidth: 3)
                        .shadow(color: Color.cyan.opacity(0.8), radius: 10, x: 0, y: 0)
                }
            }
            .frame(height: 60)
            .scaleEffect(focusedField == field ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: focusedField)
        }
    }
}
