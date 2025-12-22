//
//  PlexSettingsView.swift
//  Rivulet
//
//  Plex server connection settings
//

import SwiftUI

struct PlexSettingsView: View {
    @StateObject private var authManager = PlexAuthManager.shared
    @State private var showAuthSheet = false
    var goBack: () -> Void = {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                // Header (Menu button on remote navigates back)
                Text("Plex Server")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.top, 60)

                VStack(spacing: 24) {
                    if authManager.isAuthenticated {
                        // Connected server card
                        SettingsSection(title: "Connected Server") {
                            HStack(spacing: 16) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.green.gradient)
                                        .frame(width: 52, height: 52)

                                    Image(systemName: "checkmark")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(authManager.savedServerName ?? "Plex Server")
                                        .font(.system(size: 21, weight: .semibold))
                                        .foregroundStyle(Color(white: 0.1))

                                    if let username = authManager.username {
                                        Text("Signed in as \(username)")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color(white: 0.4))
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }

                        // Connection details
                        if let serverURL = authManager.selectedServerURL {
                            SettingsSection(title: "Connection") {
                                SettingsInfoRow(title: "Server URL", value: serverURL)
                            }
                        }

                        // Sign out
                        SettingsSection(title: "Account") {
                            SettingsActionRow(
                                title: "Sign Out",
                                isDestructive: true
                            ) {
                                authManager.signOut()
                            }
                        }
                    } else {
                        // Not connected
                        VStack(spacing: 28) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 64, weight: .thin))
                                .foregroundStyle(Color(white: 0.5))

                            VStack(spacing: 10) {
                                Text("No Server Connected")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.1))

                                Text("Connect to your Plex server to browse and stream your media library.")
                                    .font(.system(size: 19))
                                    .foregroundStyle(Color(white: 0.4))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 450)
                            }

                            ConnectButton {
                                showAuthSheet = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.white.opacity(0.85))
                        )
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .background(Color.black)
        .sheet(isPresented: $showAuthSheet) {
            PlexAuthView()
        }
    }
}

#Preview {
    PlexSettingsView()
}
