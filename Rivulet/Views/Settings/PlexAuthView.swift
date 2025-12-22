//
//  PlexAuthView.swift
//  Rivulet
//
//  PIN-based Plex authentication UI for tvOS
//

import SwiftUI

struct PlexAuthView: View {
    @StateObject private var authManager = PlexAuthManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 40) {
            switch authManager.state {
            case .idle:
                idleView

            case .requestingPin:
                loadingView(message: "Requesting PIN...")

            case .waitingForPIN(let code, _):
                pinDisplayView(code: code)

            case .selectingServer(let servers):
                serverSelectionView(servers: servers)

            case .authenticated:
                successView

            case .error(let message):
                errorView(message: message)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Idle State

    private var idleView: some View {
        VStack(spacing: 30) {
            Image(systemName: "server.rack")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Connect to Plex")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Sign in with your Plex account to access your media library.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)

            Button {
                Task {
                    await authManager.startPINAuthentication()
                }
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text("Sign In with PIN")
                }
                .font(.title3)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - PIN Display

    private func pinDisplayView(code: String) -> some View {
        VStack(spacing: 40) {
            Image(systemName: "qrcode")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            VStack(spacing: 16) {
                Text("Visit")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("plex.tv/link")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("and enter this code:")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            // PIN Code Display
            HStack(spacing: 20) {
                ForEach(Array(code), id: \.self) { char in
                    Text(String(char))
                        .font(.system(size: 72, weight: .bold, design: .monospaced))
                        .frame(width: 80, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue.opacity(0.2))
                        )
                }
            }
            .padding(.vertical, 20)

            // Loading indicator
            HStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Waiting for authentication...")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") {
                authManager.cancelAuthentication()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Server Selection

    private func serverSelectionView(servers: [PlexDevice]) -> some View {
        VStack(spacing: 30) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Select Your Server")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Choose which Plex server to connect to:")
                .font(.title3)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(servers, id: \.clientIdentifier) { server in
                        ServerRowButton(server: server) {
                            authManager.selectServer(server)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 400)

            Button("Cancel") {
                authManager.reset()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(.green)

            Text("Connected!")
                .font(.largeTitle)
                .fontWeight(.bold)

            if let serverName = authManager.savedServerName {
                Text("Connected to \(serverName)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if let username = authManager.username {
                Text("Signed in as \(username)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear {
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                dismiss()
            }
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 30) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.red)

            Text("Connection Failed")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            Button("Try Again") {
                authManager.reset()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Loading View

    private func loadingView(message: String) -> some View {
        VStack(spacing: 30) {
            ProgressView()
                .scaleEffect(2)

            Text(message)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Server Row Button

struct ServerRowButton: View {
    let server: PlexDevice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: "server.rack")
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    HStack(spacing: 8) {
                        if server.owned == true {
                            Label("Owned", systemImage: "person.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        if let conn = server.connections.first {
                            Text(conn.local ? "Local" : "Remote")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PlexAuthView()
}
