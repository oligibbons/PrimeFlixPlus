import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onBack: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Pane: Header & Info
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.cyan)
                
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("PrimeFlix+ (tvOS 15)")
                    .foregroundColor(.gray)
                
                if let msg = viewModel.message {
                    Text(msg)
                        .foregroundColor(.yellow)
                        .fontWeight(.semibold)
                        .padding(.top, 20)
                }
                
                Spacer()
                
                Button("Back to Home", action: onBack)
                    .padding(.bottom, 40)
            }
            .frame(width: 400)
            .padding(50)
            .background(Color(white: 0.1))
            
            // Right Pane: Options List
            List {
                Section(header: Text("Playlists").font(.headline).foregroundColor(.cyan)) {
                    if viewModel.playlists.isEmpty {
                        Text("No playlists added")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(viewModel.playlists) { playlist in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(playlist.title)
                                        .fontWeight(.bold)
                                    Text(playlist.url)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Button("Sync") {
                                    Task { await viewModel.syncPlaylist(playlist) }
                                }
                                
                                Button(role: .destructive) {
                                    viewModel.deletePlaylist(playlist)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                
                Section(header: Text("General").font(.headline).foregroundColor(.cyan)) {
                    Button("Clear Cache") {
                        // Implement cache clearing
                    }
                    Button("About") {
                        // Show info
                    }
                }
            }
            .listStyle(.grouped)
        }
        .background(Color.black)
        .onAppear {
            viewModel.configure(repository: repository)
        }
    }
}
