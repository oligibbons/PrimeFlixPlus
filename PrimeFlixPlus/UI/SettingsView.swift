import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onBack: () -> Void
    
    // Explicit focus control for tvOS 15
    @FocusState private var focusedField: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 50) {
            
            // LEFT PANE: Navigation & Info
            VStack(alignment: .leading, spacing: 20) {
                
                // Back Button
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Back to Home")
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.card)
                .focused($focusedField, equals: "back")
                
                Spacer().frame(height: 20)
                
                // Branding
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
                
                Spacer()
            }
            .frame(width: 350)
            .padding(50)
            .background(Color(white: 0.1))
            
            // RIGHT PANE: Content
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    
                    // SECTION: Playlists
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Manage Playlists")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        if viewModel.playlists.isEmpty {
                            // Make this focusable so the user isn't trapped if list is empty
                            Button(action: {}) {
                                Text("No playlists found")
                                    .foregroundColor(.gray)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(true)
                        } else {
                            ForEach(viewModel.playlists, id: \.self) { playlist in
                                PlaylistRow(playlist: playlist, viewModel: viewModel)
                            }
                        }
                    }
                    
                    Divider().background(Color.gray)
                    
                    // SECTION: General
                    VStack(alignment: .leading, spacing: 15) {
                        Text("General")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        Button(action: {
                            // Cache clear logic
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
            // tvOS 15 Focus Fix: Force focus to back button after load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = "back"
            }
        }
    }
}

// Subview for Rows
struct PlaylistRow: View {
    @ObservedObject var playlist: Playlist
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        HStack(spacing: 20) {
            // Text Info
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
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.card)
            
            // Delete Button
            Button(role: .destructive, action: {
                viewModel.deletePlaylist(playlist)
            }) {
                Image(systemName: "trash")
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .foregroundColor(.red)
            }
            .buttonStyle(.card)
        }
        .padding(16)
        .background(Color(white: 0.15))
        .cornerRadius(12)
    }
}
