import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onBack: () -> Void
    
    // Explicit focus control
    @FocusState private var focusedField: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 50) {
            
            // LEFT PANE: Navigation
            VStack(alignment: .leading, spacing: 20) {
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
                VStack(alignment: .leading, spacing: 30) {
                    
                    // --- FOCUS BRIDGE ---
                    // This button ensures you can always move RIGHT from the back button
                    Button(action: {
                        Task { await repository.syncAll() }
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync All Playlists")
                            Spacer()
                        }
                        .padding()
                    }
                    .buttonStyle(.card)
                    .focused($focusedField, equals: "syncAll")
                    
                    Divider().background(Color.gray)
                    
                    // Playlists Section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Manage Playlists")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        if viewModel.playlists.isEmpty {
                            Text("No playlists added yet.")
                                .foregroundColor(.gray)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(viewModel.playlists, id: \.self) { playlist in
                                PlaylistRow(playlist: playlist, viewModel: viewModel)
                            }
                        }
                    }
                    
                    Divider().background(Color.gray)
                    
                    // General Section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("General")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        Button(action: {
                            // Clear cache logic
                        }) {
                            HStack {
                                Image(systemName: "trash")
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
            // Force focus to start on Back button
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
