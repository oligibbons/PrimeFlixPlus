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
                    NeonTextField(
                        title: "SERVER URL",
                        text: $viewModel.serverUrl,
                        contentType: .URL
                    )
                    .focused($focusedField, equals: .url)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .username }
                    
                    NeonTextField(
                        title: "USERNAME",
                        text: $viewModel.username,
                        contentType: .username
                    )
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    
                    NeonTextField(
                        title: "PASSWORD",
                        text: $viewModel.password,
                        isSecure: true,
                        contentType: .password
                    )
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit { focusedField = .connectButton }
                    
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .fontWeight(.semibold)
                    }
                    
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
            
            // FIX: Lowered delay to 0.05s so it grabs focus instantly
            // before you have time to click it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if self.focusedField == nil {
                    self.focusedField = .url
                }
            }
        }
    }
}
