// oligibbons/primeflixplus/PrimeFlixPlus-2905e8f1ef297ec80428d1d457d9180e78b21452/PrimeFlixPlus/UI/NetworkSpeedTestView.swift

import SwiftUI

struct NetworkSpeedTestView: View {
    @StateObject private var viewModel = NetworkSpeedTester()
    var onBack: () -> Void
    
    @State private var pulse: Bool = false
    @State private var rotation: Double = 0
    @State private var showAdvancedMetrics: Bool = false
    
    var body: some View {
        ZStack {
            // 1. Background
            CinemeltTheme.mainBackground.ignoresSafeArea()
            
            // 2. Content determined by test stage
            switch viewModel.stage {
            case .idle, .initialCheck, .download, .processing:
                runningState
            case .complete:
                resultsState
            case .failed:
                errorState
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulse = true
            }
            Task { await viewModel.startTest() }
        }
        .onExitCommand {
            if viewModel.stage == .idle || viewModel.stage == .complete || viewModel.stage == .failed {
                onBack()
            }
        }
    }
    
    // MARK: - Running State
    
    private var runningState: some View {
        VStack(spacing: 50) {
            ZStack {
                // Outer Pulse
                Circle()
                    .stroke(CinemeltTheme.accent.opacity(0.3), lineWidth: 4)
                    .frame(width: 250, height: 250)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                    .opacity(pulse ? 0.0 : 1.0)
                
                // Inner Spinner
                Circle()
                    .trim(from: 0, to: 0.8)
                    .stroke(CinemeltTheme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(Angle(degrees: rotation))
                
                // Speed Readout
                VStack(spacing: 5) {
                    Text("\(String(format: "%.1f", viewModel.currentSpeedMbps))")
                        .font(CinemeltTheme.fontTitle(60))
                        .foregroundColor(CinemeltTheme.cream)
                        .monospacedDigit()
                    Text("Mbps")
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(CinemeltTheme.accent)
                }
            }
            
            VStack(spacing: 15) {
                Text(viewModel.currentStatus)
                    .font(CinemeltTheme.fontBody(30))
                    .foregroundColor(CinemeltTheme.cream)
                
                // Live VPN Badge
                if viewModel.isVpnActive {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                        Text("VPN Active")
                    }
                    .font(CinemeltTheme.fontBody(20))
                    .foregroundColor(.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
                }
                
                ProgressView(value: viewModel.progressPercent)
                    .progressViewStyle(.linear)
                    .tint(CinemeltTheme.accent)
                    .frame(width: 400)
                    .scaleEffect(x: 1, y: 3, anchor: .center)
            }
        }
    }
    
    // MARK: - Results State
    
    private var resultsState: some View {
        VStack(spacing: 50) {
            
            Text("Test Complete")
                .font(CinemeltTheme.fontTitle(70))
                .foregroundColor(CinemeltTheme.accent)
                .cinemeltGlow()
            
            HStack(alignment: .top, spacing: 60) {
                
                // Left Column: Quality Score
                VStack(spacing: 20) {
                    Text("Expected Stream Quality")
                        .font(CinemeltTheme.fontTitle(32))
                        .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                    
                    Text(viewModel.result?.expectedQuality ?? "Unknown")
                        .font(CinemeltTheme.fontTitle(50))
                        .foregroundColor(CinemeltTheme.cream)
                        .multilineTextAlignment(.center)
                        .shadow(color: CinemeltTheme.accent.opacity(0.5), radius: 15)
                    
                    if let res = viewModel.result {
                        Text("\(String(format: "%.1f", res.downloadSpeedMbps)) Mbps")
                            .font(CinemeltTheme.fontBody(28))
                            .foregroundColor(CinemeltTheme.accent)
                    }
                }
                .frame(width: 400)
                
                // Right Column: VPN & Network Details (NEW)
                VStack(alignment: .leading, spacing: 20) {
                    Text("Connection Details")
                        .font(CinemeltTheme.fontTitle(32))
                        .foregroundColor(CinemeltTheme.cream.opacity(0.8))
                    
                    if let res = viewModel.result {
                        VStack(alignment: .leading, spacing: 15) {
                            detailRow(icon: "lock.shield.fill",
                                      key: "VPN Status",
                                      value: res.vpnActive ? "Protected" : "Unprotected",
                                      color: res.vpnActive ? .green : .red)
                            
                            detailRow(icon: "mappin.circle.fill",
                                      key: "Location",
                                      value: res.location)
                            
                            detailRow(icon: "network",
                                      key: "ISP",
                                      value: res.ispName)
                            
                            detailRow(icon: "globe",
                                      key: "Public IP",
                                      value: res.publicIP)
                        }
                        .padding(30)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(20)
                    }
                }
                .frame(width: 450)
            }
            
            // Advanced Toggle
            Button(action: {
                withAnimation { showAdvancedMetrics.toggle() }
            }) {
                HStack {
                    Image(systemName: showAdvancedMetrics ? "chevron.up" : "chevron.down")
                    Text(showAdvancedMetrics ? "Hide Latency" : "View Latency & Jitter")
                }
                .font(CinemeltTheme.fontBody(24))
                .foregroundColor(CinemeltTheme.cream.opacity(0.9))
                .padding(.horizontal, 30)
                .padding(.vertical, 15)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
            }
            .buttonStyle(CinemeltCardButtonStyle())
            
            if showAdvancedMetrics, let result = viewModel.result {
                HStack(spacing: 50) {
                    MetricPill(title: "Latency", value: "\(result.latencyMs)", unit: "ms", icon: "gauge.circle.fill", color: CinemeltTheme.cream.opacity(0.8))
                    MetricPill(title: "Jitter", value: "\(result.jitterMs)", unit: "ms", icon: "bolt.circle.fill", color: CinemeltTheme.cream.opacity(0.8))
                }
                .padding(20)
                .cinemeltGlass(radius: 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Button(action: onBack) {
                Text("Done")
                    .font(CinemeltTheme.fontTitle(32))
                    .foregroundColor(.black)
                    .frame(width: 300)
                    .padding(.vertical, 18)
                    .background(CinemeltTheme.accent)
                    .cornerRadius(16)
            }
            .buttonStyle(CinemeltCardButtonStyle())
        }
    }
    
    private func detailRow(icon: String, key: String, value: String, color: Color = CinemeltTheme.cream) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(key)
                .foregroundColor(.gray)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .foregroundColor(color)
                .fontWeight(.bold)
                .lineLimit(1)
        }
        .font(CinemeltTheme.fontBody(22))
    }
    
    private var errorState: some View {
        VStack(spacing: 30) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 100))
                .foregroundColor(.red)
            Text("Network Test Failed")
                .font(CinemeltTheme.fontTitle(50))
                .foregroundColor(CinemeltTheme.cream)
            Text(viewModel.currentStatus)
                .font(CinemeltTheme.fontBody(26))
                .foregroundColor(.gray)
            Button("Try Again") {
                Task { await viewModel.startTest() }
            }
            .buttonStyle(CinemeltCardButtonStyle())
            Button("Close", action: onBack)
                .buttonStyle(CinemeltCardButtonStyle())
        }
    }
}

// Re-using MetricPill from previous implementation
struct MetricPill: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            Text(title)
                .font(CinemeltTheme.fontBody(20))
                .foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 5) {
                Text(value)
                    .font(CinemeltTheme.fontTitle(40))
                    .foregroundColor(CinemeltTheme.cream)
                    .monospacedDigit()
                Text(unit)
                    .font(CinemeltTheme.fontBody(24))
                    .foregroundColor(color)
                    .offset(y: -5)
            }
        }
        .frame(minWidth: 150)
    }
}
