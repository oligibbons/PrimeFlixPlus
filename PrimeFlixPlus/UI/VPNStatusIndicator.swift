import SwiftUI

/// A small, non-intrusive indicator for the Home Screen
struct VPNStatusIndicator: View {
    @ObservedObject var vpnDetector = VPNDetector.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Dot
            Circle()
                .fill(vpnDetector.isVPNActive ? Color.green : Color.red)
                .frame(width: 12, height: 12)
                .shadow(color: (vpnDetector.isVPNActive ? Color.green : Color.red).opacity(0.6), radius: 5)
            
            // Text (Active/Inactive)
            Text(vpnDetector.isVPNActive ? "VPN Active" : "VPN Inactive")
                .font(CinemeltTheme.fontBody(22))
                .foregroundColor(CinemeltTheme.cream.opacity(0.9))
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
