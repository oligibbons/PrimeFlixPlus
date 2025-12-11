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
                Text("Cinemelt v2.1")
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
            .focusSection()
            
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
                        
                        // --- SECTION 2: PLAYER EXPERIENCE (NEW) ---
                        VStack(alignment: .leading, spacing: 30) {
                            Text("Player Experience")
                                .font(CinemeltTheme.fontTitle(32))
                                .foregroundColor(CinemeltTheme.accent)
                                .cinemeltGlow()
                            
                            // 1. Scrubbing Sensitivity
                            VStack(alignment: .leading, spacing: 15) {
                                HStack {
                                    Image(systemName: "hand.draw.fill")
                                        .foregroundColor(CinemeltTheme.cream)
                                    Text("Scrubbing Sensitivity")
                                        .font(CinemeltTheme.fontBody(22))
                                        .foregroundColor(CinemeltTheme.cream)
                                    Spacer()
                                    Text("\(Int(viewModel.scrubSensitivity * 100))%")
                                        .font(CinemeltTheme.fontBody(22))
                                        .fontWeight(.bold)
                                        .foregroundColor(CinemeltTheme.accent)
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 15) {
                                        ForEach(viewModel.sensitivityOptions, id: \.1) { label, value in
                                            Button(action: { viewModel.scrubSensitivity = value }) {
                                                Text(label)
                                                    .font(CinemeltTheme.fontBody(18))
                                                    .fontWeight(viewModel.scrubSensitivity == value ? .bold : .regular)
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 12)
                                                    .background(
                                                        viewModel.scrubSensitivity == value ?
                                                        CinemeltTheme.accent : Color.white.opacity(0.05)
                                                    )
                                                    .cornerRadius(12)
                                            }
                                            .buttonStyle(CinemeltCardButtonStyle())
                                            .foregroundColor(viewModel.scrubSensitivity == value ? .black : CinemeltTheme.cream)
                                        }
                                    }
                                    .padding(5) // Bloom padding
                                }
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            // 2. Subtitles
                            VStack(alignment: .leading, spacing: 15) {
                                Button(action: { viewModel.areSubtitlesEnabled.toggle() }) {
                                    HStack {
                                        Image(systemName: "captions.bubble.fill")
                                            .foregroundColor(viewModel.areSubtitlesEnabled ? CinemeltTheme.accent : .gray)
                                        Text("Subtitles")
                                            .font(CinemeltTheme.fontBody(22))
                                            .foregroundColor(CinemeltTheme.cream)
                                        Spacer()
                                        Text(viewModel.areSubtitlesEnabled ? "On" : "Off")
                                            .font(CinemeltTheme.fontBody(22))
                                            .fontWeight(.bold)
                                            .foregroundColor(viewModel.areSubtitlesEnabled ? CinemeltTheme.accent : .gray)
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                                
                                if viewModel.areSubtitlesEnabled {
                                    Text("Subtitle Size")
                                        .font(CinemeltTheme.fontBody(18))
                                        .foregroundColor(.gray)
                                        .padding(.top, 10)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 15) {
                                            ForEach(viewModel.subtitleSizes, id: \.1) { label, value in
                                                Button(action: { viewModel.subtitleScale = value }) {
                                                    Text(label)
                                                        .font(CinemeltTheme.fontBody(18 * value)) // Dynamic Preview
                                                        .fontWeight(viewModel.subtitleScale == value ? .bold : .regular)
                                                        .padding(.horizontal, 20)
                                                        .padding(.vertical, 12)
                                                        .background(
                                                            viewModel.subtitleScale == value ?
                                                            CinemeltTheme.accent : Color.white.opacity(0.05)
                                                        )
                                                        .cornerRadius(12)
                                                }
                                                .buttonStyle(CinemeltCardButtonStyle())
                                                .foregroundColor(viewModel.subtitleScale == value ? .black : CinemeltTheme.cream)
                                            }
                                        }
                                        .padding(5)
                                    }
                                }
                            }
                        }
                        .padding(40)
                        .cinemeltGlass()
                        
                        // --- SECTION 3: CONTENT & FILTERING ---
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
                        
                        // --- SECTION 4: PLAYBACK OPTIMIZATION ---
                        VStack(alignment: .leading, spacing: 30) {
                            HStack {
                                Text("Playback Optimization")
                                    .font(CinemeltTheme.fontTitle(32))
                                    .foregroundColor(CinemeltTheme.accent)
                                    .cinemeltGlow()
                                
                                Spacer()
                                
                                // The "Magic Button"
                                Button(action: { viewModel.applyStreamOptimize() }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "wand.and.stars")
                                        Text("Auto-Optimize")
                                    }
                                    .font(CinemeltTheme.fontBody(20))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(CinemeltTheme.accent.opacity(0.2))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(CinemeltTheme.accent, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(CinemeltCardButtonStyle())
                            }
                            
                            // 1. Buffer Capacity (RAM)
                            VStack(alignment: .leading, spacing: 15) {
                                HStack {
                                    Image(systemName: "memorychip")
                                        .foregroundColor(CinemeltTheme.cream)
                                    Text("Buffer Capacity (RAM)")
                                        .font(CinemeltTheme.fontBody(22))
                                        .foregroundColor(CinemeltTheme.cream)
                                    Spacer()
                                    Text("\(viewModel.bufferMemoryLimit) MB")
                                        .font(CinemeltTheme.fontBody(22))
                                        .fontWeight(.bold)
                                        .foregroundColor(CinemeltTheme.accent)
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 15) {
                                        ForEach(viewModel.bufferOptions, id: \.1) { label, value in
                                            Button(action: { viewModel.bufferMemoryLimit = value }) {
                                                Text(label)
                                                    .font(CinemeltTheme.fontBody(18))
                                                    .fontWeight(viewModel.bufferMemoryLimit == value ? .bold : .regular)
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 12)
                                                    .background(
                                                        viewModel.bufferMemoryLimit == value ?
                                                        CinemeltTheme.accent : Color.white.opacity(0.05)
                                                    )
                                                    .cornerRadius(12)
                                            }
                                            .buttonStyle(CinemeltCardButtonStyle())
                                            .foregroundColor(viewModel.bufferMemoryLimit == value ? .black : CinemeltTheme.cream)
                                        }
                                    }
                                    .padding(5)
                                }
                                
                                Text("Higher capacity allows longer pre-loading but uses more device memory.")
                                    .font(CinemeltTheme.fontBody(16))
                                    .foregroundColor(.gray)
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            // 2. Hardware Decoding & Max Resolution
                            HStack(alignment: .top, spacing: 40) {
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("Hardware Decoding")
                                        .font(CinemeltTheme.fontBody(22))
                                        .foregroundColor(CinemeltTheme.cream)
                                    
                                    Button(action: { viewModel.useHardwareDecoding.toggle() }) {
                                        HStack {
                                            Text(viewModel.useHardwareDecoding ? "Enabled (Recommended)" : "Disabled (Software)")
                                                .font(CinemeltTheme.fontBody(20))
                                            Spacer()
                                            Image(systemName: viewModel.useHardwareDecoding ? "cpu.fill" : "cpu")
                                                .foregroundColor(viewModel.useHardwareDecoding ? CinemeltTheme.accent : .gray)
                                        }
                                        .padding(15)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(12)
                                        .frame(width: 350)
                                    }
                                    .buttonStyle(CinemeltCardButtonStyle())
                                    
                                    Text("Disable if video shows green artifacts.")
                                        .font(CinemeltTheme.fontBody(16))
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("Resolution Cap")
                                        .font(CinemeltTheme.fontBody(22))
                                        .foregroundColor(CinemeltTheme.cream)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 15) {
                                            ForEach(viewModel.resolutionCaps, id: \.self) { res in
                                                Button(action: { viewModel.maxStreamResolution = res }) {
                                                    Text(res)
                                                        .font(CinemeltTheme.fontBody(20))
                                                        .fontWeight(viewModel.maxStreamResolution == res ? .bold : .regular)
                                                        .padding(.horizontal, 20)
                                                        .padding(.vertical, 12)
                                                        .background(
                                                            viewModel.maxStreamResolution == res ?
                                                            CinemeltTheme.accent : Color.white.opacity(0.05)
                                                        )
                                                        .cornerRadius(12)
                                                }
                                                .buttonStyle(CinemeltCardButtonStyle())
                                                .foregroundColor(viewModel.maxStreamResolution == res ? .black : CinemeltTheme.cream)
                                            }
                                        }
                                        .padding(5)
                                    }
                                    .frame(maxWidth: 500)
                                    
                                    Text("Automatically skips versions higher than this limit.")
                                        .font(CinemeltTheme.fontBody(16))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(40)
                        .cinemeltGlass()
                        
                        // --- SECTION 5: DATA & SYNC ---
                        VStack(alignment: .leading, spacing: 25) {
                            Text("Data & Sync")
                                .font(CinemeltTheme.fontTitle(32))
                                .foregroundColor(CinemeltTheme.accent)
                                .cinemeltGlow()
                            
                            HStack(alignment: .top, spacing: 30) {
                                VStack(spacing: 20) {
                                    ActionCard(
                                        icon: "bolt.badge.a",
                                        title: "Network Speed Test",
                                        subtitle: "Check connection quality",
                                        action: onSpeedTest
                                    )
                                    
                                    // VPN Toggle (NEW)
                                    Button(action: { viewModel.vpnAlertEnabled.toggle() }) {
                                        HStack {
                                            Image(systemName: viewModel.vpnAlertEnabled ? "lock.shield.fill" : "lock.slash.fill")
                                                .font(.title2)
                                                .foregroundColor(viewModel.vpnAlertEnabled ? .green : .gray)
                                                .frame(width: 40)
                                            
                                            VStack(alignment: .leading) {
                                                Text("VPN Warnings")
                                                    .font(CinemeltTheme.fontBody(22))
                                                    .fontWeight(.bold)
                                                    .foregroundColor(CinemeltTheme.cream)
                                                Text(viewModel.vpnAlertEnabled ? "Shown when unsafe" : "Disabled")
                                                    .font(CinemeltTheme.fontBody(16))
                                                    .foregroundColor(.gray)
                                            }
                                            
                                            Spacer()
                                            
                                            ZStack {
                                                Capsule()
                                                    .fill(viewModel.vpnAlertEnabled ? .green : Color.white.opacity(0.2))
                                                    .frame(width: 60, height: 32)
                                                
                                                Circle()
                                                    .fill(.white)
                                                    .frame(width: 24, height: 24)
                                                    .offset(x: viewModel.vpnAlertEnabled ? 14 : -14)
                                            }
                                        }
                                        .padding(20)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(16)
                                    }
                                    .buttonStyle(CinemeltCardButtonStyle())
                                }
                                
                                VStack(spacing: 20) {
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
                        
                        // --- SECTION 6: PROFILES ---
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
                    .standardSafePadding()
                }
                .background(Color.clear)
            }
            .navigationViewStyle(.stack)
            .focusSection()
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

// ActionCard and LanguageSelectionView remain unchanged from previous implementation
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
