import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onBack: () -> Void
    
    @FocusState private var focusedField: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            
            // LEFT PANE: Glass Sidebar
            VStack(alignment: .leading, spacing: 30) {
                // Back Button
                Button(action: onBack) {
                    HStack(spacing: 15) {
                        Image(systemName: "arrow.left")
                        Text("Home")
                    }
                    .font(CinemeltTheme.fontTitle(24))
                    .foregroundColor(CinemeltTheme.cream)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                }
                .buttonStyle(CinemeltCardButtonStyle())
                .focused($focusedField, equals: "back")
                
                Spacer().frame(height: 20)
                
                // Header
                VStack(alignment: .leading, spacing: 5) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 60))
                        .foregroundColor(CinemeltTheme.accent)
                        .shadow(color: CinemeltTheme.accent.opacity(0.6), radius: 15)
                    
                    Text("Settings")
                        .font(CinemeltTheme.fontTitle(50))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Version Info
                Text("PrimeFlix v1.0")
                    .font(CinemeltTheme.fontBody(18))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
            }
            .frame(width: 400)
            .padding(50)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .background(Color.black.opacity(0.3))
                    .ignoresSafeArea()
            )
            
            // RIGHT PANE: Content Scroll
            ScrollView {
                VStack(alignment: .leading, spacing: 50) {
                    
                    // --- SECTION 1: PLAYBACK ---
                    VStack(alignment: .leading, spacing: 25) {
                        Text("Playback Preferences")
                            .font(CinemeltTheme.fontTitle(32))
                            .foregroundColor(CinemeltTheme.accent)
                            .cinemeltGlow()
                        
                        // Language Selector Card
                        Button(action: { /* Handled via NavLink usually, simulating inline for now */ }) {
                            NavigationLink(destination: LanguageSelectionView(viewModel: viewModel)) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Default Language")
                                            .font(CinemeltTheme.fontBody(24))
                                            .foregroundColor(CinemeltTheme.cream)
                                        Text(viewModel.preferredLanguage)
                                            .font(CinemeltTheme.fontBody(20))
                                            .foregroundColor(CinemeltTheme.accent)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                                .padding(20)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(16)
                            }
                        }
                        .buttonStyle(CinemeltCardButtonStyle())
                        
                        // Resolution Chips
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Preferred Quality")
                                .font(CinemeltTheme.fontBody(22))
                                .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                            
                            HStack(spacing: 20) {
                                ForEach(viewModel.availableResolutions, id: \.self) { res in
                                    Button(action: { viewModel.preferredResolution = res }) {
                                        Text(res)
                                            .font(CinemeltTheme.fontBody(20))
                                            .fontWeight(viewModel.preferredResolution == res ? .bold : .regular)
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, 12)
                                            .background(
                                                viewModel.preferredResolution == res ?
                                                CinemeltTheme.accent : Color.white.opacity(0.05)
                                            )
                                            .cornerRadius(12)
                                    }
                                    .buttonStyle(CinemeltCardButtonStyle())
                                    .foregroundColor(viewModel.preferredResolution == res ? .black : CinemeltTheme.cream)
                                }
                            }
                        }
                    }
                    .padding(40)
                    .cinemeltGlass()
                    
                    // --- SECTION 2: DATA & SYNC ---
                    VStack(alignment: .leading, spacing: 25) {
                        Text("Data & Sync")
                            .font(CinemeltTheme.fontTitle(32))
                            .foregroundColor(CinemeltTheme.accent)
                            .cinemeltGlow()
                        
                        HStack(spacing: 30) {
                            ActionCard(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Force Sync",
                                subtitle: "Refresh Library",
                                action: { Task { await repository.syncAll() } }
                            )
                            
                            ActionCard(
                                icon: "trash",
                                title: "Clear Cache",
                                subtitle: "Free up space",
                                action: { viewModel.clearCache() }
                            )
                        }
                    }
                    .padding(40)
                    .cinemeltGlass()
                    
                    // --- SECTION 3: PROFILES ---
                    if !viewModel.playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 25) {
                            Text("Active Profiles")
                                .font(CinemeltTheme.fontTitle(32))
                                .foregroundColor(CinemeltTheme.accent)
                                .cinemeltGlow()
                            
                            ForEach(viewModel.playlists, id: \.self) { playlist in
                                Button(action: {}) {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                            .font(.title)
                                            .foregroundColor(CinemeltTheme.cream.opacity(0.5))
                                        
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
                                .buttonStyle(CinemeltCardButtonStyle())
                            }
                        }
                        .padding(40)
                        .cinemeltGlass()
                    }
                }
                .padding(50)
                .padding(.bottom, 100)
            }
        }
        .background(CinemeltTheme.mainBackground)
        .onAppear {
            viewModel.configure(repository: repository)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = "back"
            }
        }
        .onExitCommand { onBack() }
    }
}

// Helper View for Grid Buttons
struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(CinemeltTheme.accent)
                    .frame(width: 40)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(CinemeltTheme.fontBody(22))
                        .fontWeight(.bold)
                        .foregroundColor(CinemeltTheme.cream)
                    Text(subtitle)
                        .font(CinemeltTheme.fontBody(16))
                        .foregroundColor(.gray)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
        }
        .buttonStyle(CinemeltCardButtonStyle())
    }
}

// Subview for Language Selection
struct LanguageSelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground
            
            ScrollView {
                VStack(spacing: 30) {
                    Text("Select Language")
                        .font(CinemeltTheme.fontTitle(50))
                        .foregroundColor(CinemeltTheme.cream)
                        .padding(.bottom, 20)
                        .cinemeltGlow()
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 350))], spacing: 40) {
                        ForEach(viewModel.availableLanguages, id: \.self) { lang in
                            Button(action: {
                                viewModel.preferredLanguage = lang
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                HStack {
                                    Text(lang)
                                        .font(CinemeltTheme.fontBody(26))
                                        .fontWeight(viewModel.preferredLanguage == lang ? .bold : .regular)
                                        .foregroundColor(CinemeltTheme.cream)
                                    Spacer()
                                    if viewModel.preferredLanguage == lang {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(CinemeltTheme.accent)
                                            .font(.title2)
                                    }
                                }
                                .padding(25)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(16)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                        }
                    }
                }
                .padding(60)
            }
        }
    }
}
