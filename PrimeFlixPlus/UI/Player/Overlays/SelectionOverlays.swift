import SwiftUI

// MARK: - Resume Prompt Overlay
struct ResumePromptOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    
    // Focus state for the buttons
    @FocusState private var focusedButton: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            
            VStack(spacing: 50) {
                VStack(spacing: 15) {
                    Text("Resume Playback?")
                        .font(CinemeltTheme.fontTitle(50))
                        .foregroundColor(CinemeltTheme.cream)
                        .cinemeltGlow()
                    
                    Text("Pick up where you left off")
                        .font(CinemeltTheme.fontBody(26))
                        .foregroundColor(.gray)
                }
                
                HStack(spacing: 60) {
                    Button(action: {
                        viewModel.startPlayback(from: viewModel.resumeTime)
                    }) {
                        VStack(spacing: 15) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(CinemeltTheme.accent)
                            
                            Text("Resume")
                                .font(CinemeltTheme.fontTitle(32))
                                .foregroundColor(CinemeltTheme.cream)
                            
                            Text(PlayerTimeFormatter.string(from: viewModel.resumeTime))
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(.gray)
                        }
                        .padding(40)
                        .frame(width: 350, height: 250)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(20)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                    .focused($focusedButton) // Default focus
                    
                    Button(action: {
                        viewModel.startPlayback(from: 0)
                    }) {
                        VStack(spacing: 15) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white)
                            
                            Text("Start Over")
                                .font(CinemeltTheme.fontTitle(32))
                                .foregroundColor(CinemeltTheme.cream)
                            
                            Text("0:00:00")
                                .font(CinemeltTheme.fontBody(24))
                                .foregroundColor(.gray)
                        }
                        .padding(40)
                        .frame(width: 350, height: 250)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(20)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedButton = true
            }
        }
    }
}

// MARK: - Video Settings Overlay (Optimized)
struct VideoSettingsOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    var onClose: () -> Void
    
    // Direct Access to Global Settings for Troubleshooting
    @AppStorage("useHardwareDecoding") var useHardwareDecoding: Bool = true
    @AppStorage("bufferMemoryLimit") var bufferMemoryLimit: Int = 300
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            
            HStack(alignment: .top, spacing: 60) {
                
                // Column 1: Picture Settings (Live)
                VStack(spacing: 30) {
                    Text("Picture")
                        .font(CinemeltTheme.fontTitle(32))
                        .foregroundColor(CinemeltTheme.cream)
                    
                    // Deinterlace
                    settingButton(
                        icon: "lines.measurement.horizontal",
                        title: "Deinterlace",
                        status: viewModel.isDeinterlaceEnabled ? "On" : "Off",
                        isActive: viewModel.isDeinterlaceEnabled
                    ) {
                        viewModel.toggleDeinterlace()
                    }
                    
                    // Aspect Ratio
                    settingButton(
                        icon: "aspectratio.fill",
                        title: "Aspect Ratio",
                        status: viewModel.aspectRatio,
                        isActive: viewModel.aspectRatio != "Default"
                    ) {
                        // Cycle Ratios
                        let ratios = ["Default", "16:9", "4:3", "Fill"]
                        if let idx = ratios.firstIndex(of: viewModel.aspectRatio) {
                            let next = ratios[(idx + 1) % ratios.count]
                            viewModel.setAspectRatio(next)
                        } else {
                            viewModel.setAspectRatio("Default")
                        }
                    }
                }
                .frame(width: 300)
                
                Divider().background(Color.white.opacity(0.1))
                
                // Column 2: Performance (Requires Restart)
                VStack(spacing: 30) {
                    VStack(spacing: 5) {
                        Text("Performance")
                            .font(CinemeltTheme.fontTitle(32))
                            .foregroundColor(CinemeltTheme.cream)
                        Text("Changes apply on next playback")
                            .font(CinemeltTheme.fontBody(16))
                            .foregroundColor(.gray)
                    }
                    
                    // Hardware Decoding Toggle
                    settingButton(
                        icon: "cpu",
                        title: "Hardware Decoding",
                        status: useHardwareDecoding ? "Enabled" : "Disabled",
                        isActive: useHardwareDecoding
                    ) {
                        useHardwareDecoding.toggle()
                    }
                    
                    // Buffer Toggle (Cycle)
                    settingButton(
                        icon: "memorychip",
                        title: "Buffer Cap",
                        status: "\(bufferMemoryLimit) MB",
                        isActive: bufferMemoryLimit > 200
                    ) {
                        // Cycle: 100 -> 300 -> 500 -> 100
                        if bufferMemoryLimit == 100 { bufferMemoryLimit = 300 }
                        else if bufferMemoryLimit == 300 { bufferMemoryLimit = 500 }
                        else { bufferMemoryLimit = 100 }
                    }
                    
                    // "Optimize Connection" Magic Button
                    Button(action: {
                        // Apply Safe Defaults
                        useHardwareDecoding = true
                        bufferMemoryLimit = 300 // Safe middle ground
                        viewModel.isDeinterlaceEnabled = true
                        viewModel.toggleDeinterlace() // Toggle twice to force refresh if needed or just set
                        viewModel.setDeinterlace(true)
                    }) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("Optimize Connection")
                        }
                        .font(CinemeltTheme.fontBody(20))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(CinemeltTheme.accent)
                        .cornerRadius(12)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                }
                .frame(width: 300)
            }
            .padding(50)
            .background(Color.white.opacity(0.05))
            .cornerRadius(30)
        }
        .onExitCommand { onClose() }
    }
    
    // Helper Component for consistency
    private func settingButton(icon: String, title: String, status: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isActive ? CinemeltTheme.accent : .gray)
                    .frame(width: 40)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(CinemeltTheme.fontBody(18))
                        .foregroundColor(.gray)
                    Text(status)
                        .font(CinemeltTheme.fontBody(22))
                        .fontWeight(.bold)
                        .foregroundColor(CinemeltTheme.cream)
                }
                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(CinemeltCardButtonStyle())
    }
}

// MARK: - Track Selection Overlay (Enhanced)
struct TrackSelectionOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    var onClose: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            
            HStack(alignment: .top, spacing: 80) {
                
                // 1. Audio Column
                VStack(spacing: 20) {
                    trackColumn(title: "Audio", tracks: viewModel.audioTracks, currentIndex: viewModel.currentAudioIndex) { i in
                        viewModel.setAudioTrack(index: i)
                    }
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    SyncControl(title: "Audio Delay", value: viewModel.audioDelay, unit: "ms") { delta in
                        viewModel.setAudioDelay(viewModel.audioDelay + delta)
                    }
                }
                .frame(width: 450)
                
                Divider().background(Color.white.opacity(0.1))
                
                // 2. Subtitle Column
                VStack(spacing: 20) {
                    trackColumn(title: "Subtitles", tracks: viewModel.subtitleTracks, currentIndex: viewModel.currentSubtitleIndex) { i in
                        viewModel.setSubtitleTrack(index: i)
                    }
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    SyncControl(title: "Subtitle Delay", value: viewModel.subtitleDelay, unit: "ms") { delta in
                        viewModel.setSubtitleDelay(viewModel.subtitleDelay + delta)
                    }
                }
                .frame(width: 450)
                
            }
            .padding(50)
            .frame(height: 850)
        }
        .onExitCommand { onClose() }
    }
    
    private func trackColumn(title: String, tracks: [String], currentIndex: Int, action: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(CinemeltTheme.fontTitle(32))
                .foregroundColor(CinemeltTheme.accent)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if tracks.isEmpty {
                        Text("No tracks found")
                            .font(CinemeltTheme.fontBody(20))
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                            Button(action: { action(index) }) {
                                HStack {
                                    Text(track)
                                        .font(CinemeltTheme.fontBody(22))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    if index == currentIndex {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(CinemeltTheme.accent)
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                        }
                    }
                }
            }
            .frame(height: 300)
        }
    }
}

// Helper for Sync Adjustments
struct SyncControl: View {
    let title: String
    let value: Int
    let unit: String
    let onChange: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(CinemeltTheme.accent)
                Text(title)
                    .font(CinemeltTheme.fontBody(22))
                    .foregroundColor(.gray)
            }
            
            HStack(spacing: 20) {
                Button(action: { onChange(-50) }) {
                    Image(systemName: "minus")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(CinemeltCardButtonStyle())
                
                Text("\(value) \(unit)")
                    .font(CinemeltTheme.fontTitle(28))
                    .foregroundColor(CinemeltTheme.cream)
                    .frame(width: 140)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                
                Button(action: { onChange(50) }) {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(CinemeltCardButtonStyle())
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
        }
    }
}

// MARK: - Version Selection Overlay
struct VersionSelectionOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    var onClose: () -> Void
    @FocusState private var focusedVersion: String?
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Select Version")
                    .font(CinemeltTheme.fontTitle(40))
                    .foregroundColor(CinemeltTheme.cream)
                    .cinemeltGlow()
                
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(viewModel.alternativeVersions, id: \.url) { channel in
                            // RICH METADATA EXTRACTION
                            let info = TitleNormalizer.parse(rawTitle: channel.canonicalTitle ?? channel.title)
                            let quality = info.quality.isEmpty ? (channel.quality ?? "HD") : info.quality
                            let language = info.language ?? "Unknown"
                            let label = "\(quality) • \(language)"
                            
                            Button(action: { viewModel.switchVersion(channel) }) {
                                HStack {
                                    Text(label)
                                        .font(CinemeltTheme.fontTitle(24))
                                        .foregroundColor(.white)
                                    Spacer()
                                    if channel.url == viewModel.currentUrl {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(CinemeltTheme.accent)
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(CinemeltCardButtonStyle())
                            .focused($focusedVersion, equals: channel.url)
                        }
                    }
                    .padding(40)
                }
                .frame(width: 500, height: 600)
            }
        }
        .onExitCommand { onClose() }
    }
}

// MARK: - Auto Play Overlay
struct AutoPlayOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    @FocusState private var isPlayNowFocused: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            HStack(spacing: 60) {
                // Info
                VStack(alignment: .leading, spacing: 20) {
                    Text("Up Next")
                        .font(CinemeltTheme.fontBody(28))
                        .foregroundColor(.gray)
                    
                    if let next = viewModel.nextEpisode {
                        Text(next.title)
                            .font(CinemeltTheme.fontTitle(50))
                            .foregroundColor(CinemeltTheme.cream)
                            .lineLimit(2)
                            .cinemeltGlow()
                    }
                    
                    HStack(spacing: 15) {
                        Image(systemName: "timer")
                            .foregroundColor(CinemeltTheme.accent)
                        Text("Playing in \(viewModel.autoPlayCounter) seconds")
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(CinemeltTheme.accent)
                            .monospacedDigit()
                    }
                }
                .frame(width: 500)
                
                // Actions
                VStack(spacing: 20) {
                    Button(action: { viewModel.confirmAutoPlay() }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play Now")
                        }
                        .font(CinemeltTheme.fontTitle(28))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 20)
                        .background(CinemeltTheme.accent)
                        .cornerRadius(16)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                    .focused($isPlayNowFocused)
                    
                    Button(action: { viewModel.cancelAutoPlay() }) {
                        Text("Cancel")
                            .font(CinemeltTheme.fontBody(24))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(CinemeltCardButtonStyle())
                }
            }
        }
        .onAppear {
            isPlayNowFocused = true
        }
    }
}
