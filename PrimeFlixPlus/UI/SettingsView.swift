import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onBack: () -> Void
    
    // We don't need complex focus state here anymore; tvOS handles it naturally.
    @FocusState private var isBackFocused: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 50) {
            
            // LEFT PANE: Navigation
            VStack(alignment: .leading, spacing: 30) {
                // Back Button
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Back to Home")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .buttonStyle(.card)
                .focused($isBackFocused) // Default focus landing pad
                
                // Info Panel
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.cyan)
                    
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    if let date = repository.lastSyncDate {
                        Text("Last Sync: \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .frame(width: 350)
            .padding(50)
            .background(Color(white: 0.1))
            
            // RIGHT PANE: Content
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    
                    // SECTION 1: PLAYLISTS
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Manage Playlists")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        if viewModel.playlists.isEmpty {
                            Text("No playlists found.")
                                .foregroundColor(.gray)
                                .padding()
                        } else {
                            // Using standard buttons instead of complex custom rows
                            ForEach(viewModel.playlists, id: \.self) { playlist in
                                PlaylistRow(playlist: playlist, viewModel: viewModel)
                            }
                        }
                    }
                    
                    Divider().background(Color.gray)
                    
                    // SECTION 2: GENERAL
                    VStack(alignment: .leading, spacing: 20) {
                        Text("General")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        Button(action: {
                            // Clear cache logic
                        }) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                Text("Clear Image Cache")
                                Spacer()
                            }
                            .padding()
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(50)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            viewModel.configure(repository: repository)
        }
    }
}

// Simplified Row Component
struct PlaylistRow: View {
    @ObservedObject var playlist: Playlist
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        HStack(spacing: 20) {
            // Info (Not Focusable)
            VStack(alignment: .leading) {
                Text(playlist.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(playlist.url)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Sync Button
            Button(action: {
                Task { await viewModel.syncPlaylist(playlist) }
            }) {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.card)
            
            // Delete Button
            Button(role: .destructive, action: {
                viewModel.deletePlaylist(playlist)
            }) {
                Image(systemName: "trash")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundColor(.red)
            }
            .buttonStyle(.card)
        }
        .padding(20)
        .background(Color(white: 0.15))
        .cornerRadius(12)
    }
}
