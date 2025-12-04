import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onBack: () -> Void
    
    @FocusState private var focusedField: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            
            // LEFT PANE: Sidebar
            // Keeps the 2-pane logic you had, but styled.
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
                        .foregroundColor(CinemeltTheme.accent)
                    
                    Text("Settings")
                        .font(CinemeltTheme.fontTitle(48))
                        .foregroundColor(CinemeltTheme.cream)
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .frame(width: 350)
            .padding(40)
            .background(CinemeltTheme.backgroundEnd.opacity(0.5)) // Subtle darker pane
            .background(.ultraThinMaterial)
            .ignoresSafeArea()
            .focusSection()
            
            // RIGHT PANE: Content
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    
                    // --- SECTION 1: PLAYBACK PREFERENCES ---
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Playback Preferences")
                            .font(CinemeltTheme.fontTitle(32))
                            .foregroundColor(CinemeltTheme.accent)
                        
                        // Language Selector
                        HStack {
                            Text("Default Language")
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                                .frame(width: 250, alignment: .leading)
                            
                            NavigationLink(destination: LanguageSelectionView(viewModel: viewModel)) {
                                HStack {
                                    Text(viewModel.preferredLanguage)
                                        .font(CinemeltTheme.fontBody(24))
                                        .foregroundColor(CinemeltTheme.cream)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .frame(width: 300)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.card)
                        }
                        
                        // Resolution Buttons
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Preferred Quality")
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 20) {
                                    ForEach(viewModel.availableResolutions, id: \.self) { res in
                                        Button(action: { viewModel.preferredResolution = res }) {
                                            Text(res)
                                                .font(CinemeltTheme.fontBody(20))
                                                .fontWeight(viewModel.preferredResolution == res ? .bold : .regular)
                                                .padding(.horizontal, 24)
                                                .padding(.vertical, 12)
                                                .background(viewModel.preferredResolution == res ? CinemeltTheme.accent : Color.white.opacity(0.05))
                                                .cornerRadius(12)
                                        }
                                        .buttonStyle(.card)
                                        .foregroundColor(viewModel.preferredResolution == res ? .black : CinemeltTheme.cream)
                                    }
                                }
                                .padding(.vertical, 20)
                            }
                        }
                        
                        Text("Cinemelt will automatically select the best version based on these settings.")
                            .font(CinemeltTheme.fontBody(20))
                            .foregroundColor(.gray)
                            .padding(.top, 5)
                    }
                    .padding(40)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(20)
                    
                    // --- SECTION 2: DATA MANAGEMENT ---
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Data & Sync")
                            .font(CinemeltTheme.fontTitle(32))
                            .foregroundColor(CinemeltTheme.accent)
                        
                        HStack(spacing: 30) {
                            Button(action: {
                                Task { await repository.syncAll() }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Force Sync")
                                }
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(CinemeltTheme.cream)
                                .padding(20)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.card)
                            
                            Button(action: {
                                viewModel.clearCache()
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Clear Image Cache")
                                }
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(CinemeltTheme.cream)
                                .padding(20)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(40)
                    
                    // --- SECTION 3: PLAYLISTS ---
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Active Playlists")
                            .font(CinemeltTheme.fontTitle(32))
                            .foregroundColor(CinemeltTheme.accent)
                        
                        ForEach(viewModel.playlists, id: \.self) { playlist in
                            Button(action: {}) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(playlist.title)
                                            .font(CinemeltTheme.fontBody(24))
                                            .fontWeight(.bold)
                                            .foregroundColor(CinemeltTheme.cream)
                                        Text(playlist.url)
                                            .font(CinemeltTheme.fontBody(18))
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button(action: { viewModel.deletePlaylist(playlist) }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red.opacity(0.8))
                                            .font(.title2)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(20)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(16)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(40)
                }
                .padding(50)
            }
            .focusSection()
        }
        .background(CinemeltTheme.mainBackground.ignoresSafeArea())
        .onAppear {
            viewModel.configure(repository: repository)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = "back"
            }
        }
        .onExitCommand {
            onBack()
        }
    }
}

// Subview for Language Selection
struct LanguageSelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Select Language")
                    .font(CinemeltTheme.fontTitle(40))
                    .foregroundColor(CinemeltTheme.cream)
                    .padding(.bottom, 20)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 30) {
                    ForEach(viewModel.availableLanguages, id: \.self) { lang in
                        Button(action: {
                            viewModel.preferredLanguage = lang
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack {
                                Text(lang)
                                    .font(CinemeltTheme.fontBody(24))
                                    .fontWeight(viewModel.preferredLanguage == lang ? .bold : .regular)
                                    .foregroundColor(CinemeltTheme.cream)
                                Spacer()
                                if viewModel.preferredLanguage == lang {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(CinemeltTheme.accent)
                                }
                            }
                            .padding(20)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
            .padding(60)
        }
        .background(CinemeltTheme.mainBackground.ignoresSafeArea())
    }
}
