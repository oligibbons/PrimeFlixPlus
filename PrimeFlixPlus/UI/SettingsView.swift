import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onBack: () -> Void
    
    @FocusState private var focusedField: String?
    
    var body: some View {
        NavigationView {
            HStack(alignment: .top, spacing: 0) {
                
                // LEFT PANE: Sidebar
                VStack(alignment: .leading, spacing: 20) {
                    Button(action: onBack) {
                        HStack {
                            Image(systemName: "arrow.left")
                            Text("Home")
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.card)
                    .focused($focusedField, equals: "back")
                    
                    Spacer().frame(height: 40)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.cyan)
                        
                        Text("Settings")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
                .frame(width: 350)
                .padding(40)
                .background(Color(white: 0.1))
                .ignoresSafeArea()
                .focusSection() // CRITICAL: Tells Focus Engine this is a navigable group
                
                // RIGHT PANE: Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        
                        // --- SECTION 1: PLAYBACK PREFERENCES ---
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Playback Preferences")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                            
                            // Language Selector
                            HStack {
                                Text("Default Language")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                    .frame(width: 250, alignment: .leading)
                                
                                NavigationLink(destination: LanguageSelectionView(viewModel: viewModel)) {
                                    HStack {
                                        Text(viewModel.preferredLanguage)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .padding()
                                    .frame(width: 300)
                                }
                                .buttonStyle(.card)
                            }
                            
                            // Resolution Buttons
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Preferred Quality")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 15) {
                                        ForEach(viewModel.availableResolutions, id: \.self) { res in
                                            Button(action: { viewModel.preferredResolution = res }) {
                                                Text(res)
                                                    .fontWeight(viewModel.preferredResolution == res ? .bold : .regular)
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 10)
                                            }
                                            .buttonStyle(.card)
                                            .foregroundColor(viewModel.preferredResolution == res ? .white : .gray)
                                        }
                                    }
                                    .padding(.vertical, 20) // Add padding for focus expansion
                                }
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
                            
                            HStack(spacing: 20) {
                                Button(action: {
                                    Task { await repository.syncAll() }
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text("Force Sync")
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
                                    }
                                    .padding()
                                }
                                .buttonStyle(.card)
                            }
                        }
                        
                        // --- SECTION 3: PLAYLISTS ---
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Active Playlists")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                            
                            ForEach(viewModel.playlists, id: \.self) { playlist in
                                Button(action: {}) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(playlist.title)
                                                .fontWeight(.bold)
                                            Text(playlist.url).font(.caption).foregroundColor(.gray).lineLimit(1)
                                        }
                                        Spacer()
                                        Button(action: { viewModel.deletePlaylist(playlist) }) {
                                            Image(systemName: "trash").foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding()
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                    .padding(50)
                }
                .focusSection() // CRITICAL: Marks the scrollview as a valid destination group
            }
            .background(Color.black.ignoresSafeArea())
            .onAppear {
                viewModel.configure(repository: repository)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = "back"
                }
            }
        }
        .onExitCommand {
            onBack()
        }
        .navigationViewStyle(.stack)
    }
}

// Subview for Language Selection
struct LanguageSelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Select Language")
                    .font(.title3)
                    .foregroundColor(.gray)
                    .padding(.bottom, 20)
                
                ForEach(viewModel.availableLanguages, id: \.self) { lang in
                    Button(action: {
                        viewModel.preferredLanguage = lang
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Text(lang)
                                .fontWeight(viewModel.preferredLanguage == lang ? .bold : .regular)
                            Spacer()
                            if viewModel.preferredLanguage == lang {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.cyan)
                            }
                        }
                        .padding()
                        .frame(width: 500)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(50)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
