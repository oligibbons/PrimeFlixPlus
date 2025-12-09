import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onBack: () -> Void
    var onSpeedTest: () -> Void
    
    // Trigger for re-taking the questionnaire
    @State private var showOnboarding: Bool = false
    
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
                Text("Cinemelt v1.5")
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
            .focusSection() // FIX: Groups the sidebar as one navigation target
            
            // RIGHT PANE: Content Scroll
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 50) {
                        
                        // --- SECTION 1: PERSONALIZATION ---
                        VStack(alignment: .leading, spacing: 25) {
                            Text("Personalization")
                                .font(CinemeltTheme.fontTitle(32))
                                .foregroundColor(CinemeltTheme.accent)
                                .cinemeltGlow()
                            
                            // Re-take Taste Profile
                            ActionCard(
                                icon: "sparkles.tv.fill",
                                title: "Taste Profile",
                                subtitle: "Update genres, moods, and favorites",
                                action: { showOnboarding = true }
                            )
                        }
                        .padding(40)
                        .cinemeltGlass()
                        
                        // --- SECTION 2: CONTENT & FILTERING ---
                        VStack(alignment: .leading, spacing: 25) {
                            Text("Content Preferences")
                                .font(CinemeltTheme.fontTitle(32))
                                .foregroundColor(CinemeltTheme.accent)
                                .cinemeltGlow()
                            
                            HStack(spacing: 30) {
                                // Language Selector
                                NavigationLink(destination: LanguageSelectionView(viewModel: viewModel)) {
                                    HStack {
                                        Image(systemName: "globe")
                                            .font(.title2)
                                            .foregroundColor(CinemeltTheme.accent)
                                        
                                        VStack(alignment: .leading) {
                                            Text("Language")
                                                .font(CinemeltTheme.fontBody(22))
                                                .fontWeight(.bold)
                                                .foregroundColor(CinemeltTheme.cream)
                                            Text(viewModel.preferredLanguage)
                                                .font(CinemeltTheme.fontBody(16))
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .padding(20)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(16)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                                
                                // Category Manager
                                NavigationLink(destination: ManageCategoriesView(viewModel: viewModel)) {
                                    HStack {
                                        Image(systemName: "list.bullet.rectangle.portrait")
                                            .font(.title2)
                                            .foregroundColor(CinemeltTheme.accent)
                                        
                                        VStack(alignment: .leading) {
                                            Text("Categories")
                                                .font(CinemeltTheme.fontBody(22))
                                                .fontWeight(.bold)
                                                .foregroundColor(CinemeltTheme.cream)
                                            Text("Unhide specific items")
                                                .font(CinemeltTheme.fontBody(16))
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .padding(20)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(16)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                            }
                            
                            // Auto-Hide Custom Toggle
                            Button(action: {
                                viewModel.autoHideForeign.toggle()
                                if viewModel.autoHideForeign {
                                    viewModel.runAutoHidingLogic()
                                }
                            }) {
                                HStack {
                                    Image(systemName: viewModel.autoHideForeign ? "eye.slash.fill" : "eye")
                                        .foregroundColor(CinemeltTheme.accent)
                                        .font(.title2)
                                        .frame(width: 40)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Auto-Hide Foreign Content")
                                            .font(CinemeltTheme.fontBody(22))
                                            .fontWeight(.bold)
                                            .foregroundColor(CinemeltTheme.cream)
                                        
                                        Text(viewModel.autoHideForeign ? "Hiding categories not in \(viewModel.preferredLanguage)" : "Show all content languages")
                                            .font(CinemeltTheme.fontBody(16))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    ZStack {
                                        Capsule()
                                            .fill(viewModel.autoHideForeign ? CinemeltTheme.accent : Color.white.opacity(0.2))
                                            .frame(width: 60, height: 32)
                                        
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 24, height: 24)
                                            .offset(x: viewModel.autoHideForeign ? 14 : -14)
                                    }
                                }
                                .padding(20)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(16)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                        }
                        .padding(40)
                        .cinemeltGlass()
                        
                        // --- SECTION 3: PLAYBACK ---
                        VStack(alignment: .leading, spacing: 25) {
                            Text("Playback")
                                .font(CinemeltTheme.fontTitle(32))
                                .foregroundColor(CinemeltTheme.accent)
                                .cinemeltGlow()
                            
                            // Row 1: Quality & Speed
                            HStack(alignment: .top, spacing: 40) {
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
                                
                                Spacer()
                                
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("Default Speed")
                                        .font(CinemeltTheme.fontBody(22))
                                        .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 15) {
                                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                                                Button(action: { viewModel.defaultPlaybackSpeed = speed }) {
                                                    Text("\(String(format: "%g", speed))x")
                                                        .font(CinemeltTheme.fontBody(20))
                                                        .fontWeight(viewModel.defaultPlaybackSpeed == speed ? .bold : .regular)
                                                        .padding(.horizontal, 20)
                                                        .padding(.vertical, 12)
                                                        .background(
                                                            viewModel.defaultPlaybackSpeed == speed ?
                                                            CinemeltTheme.accent : Color.white.opacity(0.05)
                                                        )
                                                        .cornerRadius(12)
                                                }
                                                .buttonStyle(CinemeltCardButtonStyle())
                                                .foregroundColor(viewModel.defaultPlaybackSpeed == speed ? .black : CinemeltTheme.cream)
                                            }
                                        }
                                        .padding(10)
                                    }
                                    .frame(maxWidth: 600)
                                }
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            // Row 2: Default Video Settings (NEW)
                            HStack(alignment: .top, spacing: 40) {
                                // Deinterlace
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("Deinterlace Mode")
                                        .font(CinemeltTheme.fontBody(22))
                                        .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                                    
                                    Button(action: { viewModel.defaultDeinterlace.toggle() }) {
                                        HStack {
                                            Text(viewModel.defaultDeinterlace ? "Always On" : "Auto (Live Only)")
                                                .font(CinemeltTheme.fontBody(20))
                                                .fontWeight(viewModel.defaultDeinterlace ? .bold : .regular)
                                            
                                            Spacer()
                                            
                                            Image(systemName: viewModel.defaultDeinterlace ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(viewModel.defaultDeinterlace ? CinemeltTheme.accent : .gray)
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(12)
                                        .frame(width: 250)
                                    }
                                    .buttonStyle(CinemeltCardButtonStyle())
                                }
                                
                                Spacer()
                                
                                // Aspect Ratio
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("Default Aspect Ratio")
                                        .font(CinemeltTheme.fontBody(22))
                                        .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 15) {
                                            ForEach(["Default", "16:9", "4:3", "Fill"], id: \.self) { ratio in
                                                Button(action: { viewModel.defaultAspectRatio = ratio }) {
                                                    Text(ratio)
                                                        .font(CinemeltTheme.fontBody(20))
                                                        .fontWeight(viewModel.defaultAspectRatio == ratio ? .bold : .regular)
                                                        .padding(.horizontal, 20)
                                                        .padding(.vertical, 12)
                                                        .background(
                                                            viewModel.defaultAspectRatio == ratio ?
                                                            CinemeltTheme.accent : Color.white.opacity(0.05)
                                                        )
                                                        .cornerRadius(12)
                                                }
                                                .buttonStyle(CinemeltCardButtonStyle())
                                                .foregroundColor(viewModel.defaultAspectRatio == ratio ? .black : CinemeltTheme.cream)
                                            }
                                        }
                                        .padding(10)
                                    }
                                    .frame(maxWidth: 600)
                                }
                            }
                        }
                        .padding(40)
                        .cinemeltGlass()
                        
                        // --- SECTION 4: DATA & SYNC ---
                        VStack(alignment: .leading, spacing: 25) {
                            Text("Data & Sync")
                                .font(CinemeltTheme.fontTitle(32))
                                .foregroundColor(CinemeltTheme.accent)
                                .cinemeltGlow()
                            
                            ActionCard(
                                icon: "bolt.badge.a",
                                title: "Network Speed Test",
                                subtitle: "Check connection quality for streaming",
                                action: onSpeedTest
                            )
                            
                            HStack(spacing: 30) {
                                ActionCard(
                                    icon: "arrow.triangle.2.circlepath",
                                    title: "Update Library",
                                    subtitle: "Fetch new content",
                                    action: { viewModel.forceUpdate() }
                                )
                                
                                Button(action: { viewModel.nuclearResync() }) {
                                    HStack(spacing: 15) {
                                        Image(systemName: "exclamationmark.arrow.circlepath")
                                            .font(.title)
                                            .foregroundColor(.red)
                                            .frame(width: 40)
                                        
                                        VStack(alignment: .leading) {
                                            Text("Nuclear Resync")
                                                .font(CinemeltTheme.fontBody(22))
                                                .fontWeight(.bold)
                                                .foregroundColor(.red.opacity(0.9))
                                            Text("Wipe and rebuild all data")
                                                .font(CinemeltTheme.fontBody(16))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(20)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.05))
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                            }
                            
                            ActionCard(
                                icon: "trash",
                                title: "Clear Image Cache",
                                subtitle: "Free up disk space",
                                action: { viewModel.clearCache() }
                            )
                        }
                        .padding(40)
                        .cinemeltGlass()
                        
                        // --- SECTION 5: PROFILES ---
                        if !viewModel.playlists.isEmpty {
                            VStack(alignment: .leading, spacing: 25) {
                                Text("Active Profiles")
                                    .font(CinemeltTheme.fontTitle(32))
                                    .foregroundColor(CinemeltTheme.accent)
                                    .cinemeltGlow()
                                
                                ForEach(viewModel.playlists, id: \.self) { playlist in
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
                                        .buttonStyle(CinemeltCardButtonStyle())
                                        .frame(width: 50, height: 50)
                                    }
                                    .padding(20)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(16)
                                }
                            }
                            .padding(40)
                            .cinemeltGlass()
                        }
                    }
                    .padding(50)
                    .padding(.bottom, 100)
                }
                .background(Color.clear)
            }
            .navigationViewStyle(.stack)
            .focusSection() // FIX: Groups the content area as one navigation target
        }
        .background(CinemeltTheme.mainBackground)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(onComplete: { showOnboarding = false })
        }
        .onAppear {
            viewModel.configure(repository: repository)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = "back"
            }
        }
        .onExitCommand { onBack() }
    }
}

// (ActionCard and LanguageSelectionView reused from previous file)
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

struct LanguageSelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
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
                                if viewModel.autoHideForeign {
                                    viewModel.runAutoHidingLogic()
                                }
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
