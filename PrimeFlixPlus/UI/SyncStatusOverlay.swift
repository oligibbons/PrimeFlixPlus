// oligibbons/primeflixplus/PrimeFlixPlus-d5b2deac233716cf4e62244788059449d29d9f26/PrimeFlixPlus/UI/SyncStatusOverlay.swift

import SwiftUI

struct SyncStatusOverlay: View {
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var body: some View {
        VStack {
            // 1. The Toast Content
            if let message = repository.syncStatusMessage {
                HStack(spacing: 16) {
                    // Status Icon
                    if repository.isErrorState {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.3))
                            .font(.title3)
                    } else if repository.isSyncing {
                        ProgressView()
                            .tint(CinemeltTheme.accent)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(CinemeltTheme.accent)
                            .font(.title3)
                    }
                    
                    // Message
                    Text(message)
                        .font(CinemeltTheme.fontBody(24))
                        .foregroundColor(CinemeltTheme.cream)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                // Glowing border
                .overlay(
                    Capsule()
                        .stroke(
                            repository.isErrorState ? Color.red.opacity(0.5) : CinemeltTheme.accent.opacity(0.5),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 60) // Safe Area inset to push it down slightly from the bezel
            }
            
            // 2. Pusher to force top alignment
            Spacer()
        }
        // 3. Frame & Interaction Settings
        // Forces the VStack to fill the screen so alignment works...
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // ... but strictly ignore all touches so swipes pass through to the app.
        .allowsHitTesting(false)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: repository.syncStatusMessage)
    }
}
