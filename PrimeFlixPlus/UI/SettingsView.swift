import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onBack: () -> Void
    
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
                }
                
                Spacer()
            }
            .frame(width: 350)
            .padding(50)
            .background(Color(white: 0.1))
            
            // RIGHT PANE: Content
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    
                    // --- SECTION 1: PLAYBACK PREFERENCES (NEW) ---
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Playback Preferences")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        // Language Picker
                        HStack {
                            Text("Default Language")
                                .font(.headline)
                                .foregroundColor(.gray)
                                .frame(width: 200, alignment: .leading)
                            
                            Picker("", selection: $viewModel.preferredLanguage) {
                                ForEach(viewModel.availableLanguages, id: \.self) { lang in
                                    Text(lang).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 300)
                        }
                        
                        // Resolution Picker
                        HStack {
                            Text("Preferred Quality")
                                .font(.headline)
                                .foregroundColor(.gray)
                                .frame(width: 200, alignment: .leading)
                            
                            Picker("", selection: $viewModel.preferredResolution) {
                                ForEach(viewModel.availableResolutions, id: \.self) { res in
                                    Text(res).tag(res)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 300)
                        }
                        
                        Text("PrimeFlix+ will automatically try to select the best version matching these preferences.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 5)
                    }
                    .padding(30)
                    .background(Color(white: 0.15))
                    .cornerRadius(20)
                    
                    // --- SECTION 2: DATA MANAGEMENT ---
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Data & Sync")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        Button(action: {
                            Task { await repository.syncAll() }
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Force Sync All Playlists")
                                Spacer()
                            }
                            .padding()
                        }
                        .buttonStyle(.card)
                        
                        Button(action: {
                            viewModel.clearCache()
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
                    
                    // --- SECTION 3: PLAYLISTS ---
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Active Playlists")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        ForEach(viewModel.playlists, id: \.self) { playlist in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(playlist.title)
                                        .fontWeight(.bold)
                                    Text(playlist.url).font(.caption).foregroundColor(.gray).lineLimit(1)
                                }
                                Spacer()
                                Button(role: .destructive, action: { viewModel.deletePlaylist(playlist) }) {
                                    Image(systemName: "trash").foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .background(Color(white: 0.12))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(50)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            viewModel.configure(repository: repository)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = "back"
            }
        }
        // Menu Button Handler
        .onExitCommand {
            onBack()
        }
    }
}
