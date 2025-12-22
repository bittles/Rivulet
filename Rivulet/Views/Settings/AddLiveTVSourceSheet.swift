//
//  AddLiveTVSourceSheet.swift
//  Rivulet
//
//  Sheet for adding a new Live TV source (Plex or M3U)
//

import SwiftUI

struct AddLiveTVSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dataStore = LiveTVDataStore.shared
    @StateObject private var authManager = PlexAuthManager.shared

    @State private var selectedSourceType: LiveTVSourceType?
    @State private var isCheckingPlex = false
    @State private var plexLiveTVAvailable: Bool?
    @State private var plexError: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("Add Live TV Source")
                        .font(.system(size: 28, weight: .bold))

                    Spacer()

                    // Invisible spacer for alignment
                    Button("Cancel") { }
                        .buttonStyle(.bordered)
                        .opacity(0)
                }
                .padding(.horizontal, 40)
                .padding(.top, 32)
                .padding(.bottom, 24)

                if let sourceType = selectedSourceType {
                    // Configuration form for selected source type
                    configurationView(for: sourceType)
                } else {
                    // Source type picker
                    sourceTypePicker
                }
            }
            .frame(maxWidth: 800)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(40)
        }
    }

    // MARK: - Source Type Picker

    private var sourceTypePicker: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                Text("Choose Source Type")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                // Plex Live TV option (only if authenticated)
                if authManager.isAuthenticated {
                    SourceTypeButton(
                        icon: "play.rectangle.fill",
                        iconColor: .orange,
                        title: "Plex Live TV",
                        subtitle: "Use Live TV from your Plex server",
                        isLoading: isCheckingPlex
                    ) {
                        checkPlexLiveTV()
                    }
                }

                // M3U Server option (Dispatcharr-style with auto EPG)
                SourceTypeButton(
                    icon: "server.rack",
                    iconColor: .blue,
                    title: "M3U Server",
                    subtitle: "Server with M3U and EPG endpoints"
                ) {
                    selectedSourceType = .dispatcharr
                }

                // Generic M3U option
                SourceTypeButton(
                    icon: "list.bullet.rectangle",
                    iconColor: .green,
                    title: "M3U Playlist",
                    subtitle: "Add any M3U/M3U8 playlist URL"
                ) {
                    selectedSourceType = .genericM3U
                }

                // Error message for Plex
                if let error = plexError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                }

                // Plex not connected hint
                if !authManager.isAuthenticated {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Connect your Plex server in Settings to access Plex Live TV")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Configuration Views

    @ViewBuilder
    private func configurationView(for sourceType: LiveTVSourceType) -> some View {
        switch sourceType {
        case .plex:
            PlexLiveTVConfigView(onComplete: { dismiss() }, onBack: { selectedSourceType = nil })
        case .dispatcharr:
            DispatcharrConfigView(onComplete: { dismiss() }, onBack: { selectedSourceType = nil })
        case .genericM3U:
            M3UConfigView(onComplete: { dismiss() }, onBack: { selectedSourceType = nil })
        }
    }

    // MARK: - Plex Live TV Check

    private func checkPlexLiveTV() {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else {
            plexError = "Plex server not connected"
            return
        }

        isCheckingPlex = true
        plexError = nil

        Task {
            let isAvailable = await PlexLiveTVProvider.checkAvailability(
                serverURL: serverURL,
                authToken: token
            )

            await MainActor.run {
                isCheckingPlex = false
                if isAvailable {
                    selectedSourceType = .plex
                } else {
                    plexError = "Plex Live TV is not available on this server. Make sure you have a tuner configured."
                }
            }
        }
    }
}

// MARK: - Source Type Button

struct SourceTypeButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var isLoading: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 60, height: 60)

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isFocused ? Color.primary.opacity(0.15) : Color.primary.opacity(0.08))
        )
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            if !isLoading {
                action()
            }
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Plex Live TV Config

struct PlexLiveTVConfigView: View {
    let onComplete: () -> Void
    let onBack: () -> Void

    @StateObject private var authManager = PlexAuthManager.shared
    @StateObject private var dataStore = LiveTVDataStore.shared
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            // Back button
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.horizontal, 40)

            Spacer()

            // Icon and info
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(.orange.gradient)
                        .frame(width: 100, height: 100)

                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Add Plex Live TV")
                        .font(.system(size: 32, weight: .bold))

                    if let serverName = authManager.savedServerName {
                        Text("From \(serverName)")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("This will add Live TV channels from your Plex server. You'll be able to watch live channels and see the program guide.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 16))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Add button
            Button {
                addPlexLiveTV()
            } label: {
                HStack(spacing: 10) {
                    if isAdding {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isAdding ? "Adding..." : "Add Plex Live TV")
                        .font(.system(size: 21, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.orange)
                )
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
            .padding(.bottom, 40)
        }
    }

    private func addPlexLiveTV() {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken,
              let serverName = authManager.savedServerName else {
            errorMessage = "Plex server not connected"
            return
        }

        isAdding = true
        errorMessage = nil

        Task {
            let provider = PlexLiveTVProvider(
                serverURL: serverURL,
                authToken: token,
                serverName: serverName
            )

            await dataStore.addPlexSource(provider: provider)

            // Load channels immediately
            await dataStore.loadChannels()

            await MainActor.run {
                isAdding = false
                onComplete()
            }
        }
    }
}

// MARK: - M3U Server Config

struct DispatcharrConfigView: View {
    let onComplete: () -> Void
    let onBack: () -> Void

    @StateObject private var dataStore = LiveTVDataStore.shared
    @State private var serverURL = ""
    @State private var displayName = "Live TV"
    @State private var isAdding = false
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var validationStatus: ValidationStatus = .idle

    @FocusState private var focusedField: Field?

    enum Field {
        case url, name
    }

    enum ValidationStatus {
        case idle
        case validating
        case valid(channelCount: Int)
        case invalid(String)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                // Back button
                HStack {
                    Button {
                        onBack()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.horizontal, 40)

                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.blue.gradient)
                            .frame(width: 80, height: 80)

                        Image(systemName: "server.rack")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text("Add M3U Server")
                        .font(.system(size: 28, weight: .bold))
                }
                .padding(.top, 8)

                // Form
                VStack(spacing: 20) {
                    // Server URL field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server URL")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("http://192.168.1.100:9191", text: $serverURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                            .focused($focusedField, equals: .url)
                            .autocorrectionDisabled()
                            #if os(tvOS)
                            .keyboardType(.URL)
                            #endif

                        Text("Base URL of your M3U server (expects /output/m3u and /output/epg)")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    // Display name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display Name")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("Live TV", text: $displayName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                            .focused($focusedField, equals: .name)
                    }

                    // Validation status
                    validationStatusView
                }
                .padding(.horizontal, 40)

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 16))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                // Buttons
                HStack(spacing: 16) {
                    Button("Validate") {
                        validateServer()
                    }
                    .buttonStyle(.bordered)
                    .disabled(serverURL.isEmpty || isValidating)

                    Button {
                        addDispatcharr()
                    } label: {
                        HStack(spacing: 10) {
                            if isAdding {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isAdding ? "Adding..." : "Add Source")
                                .font(.system(size: 19, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(canAdd ? Color.blue : Color.gray)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd || isAdding)
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private var validationStatusView: some View {
        switch validationStatus {
        case .idle:
            EmptyView()
        case .validating:
            HStack(spacing: 10) {
                ProgressView()
                Text("Checking server...")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        case .valid(let count):
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Connected! Found \(count) channels")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
            }
        case .invalid(let message):
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(.red)
            }
        }
    }

    private var canAdd: Bool {
        if case .valid = validationStatus {
            return !serverURL.isEmpty && !displayName.isEmpty
        }
        // Allow adding without validation, but prefer validated
        return !serverURL.isEmpty && !displayName.isEmpty
    }

    private func validateServer() {
        guard let service = DispatcharrService.create(from: serverURL) else {
            validationStatus = .invalid("Invalid URL format")
            return
        }

        validationStatus = .validating

        Task {
            do {
                let channels = try await service.fetchChannels()
                await MainActor.run {
                    validationStatus = .valid(channelCount: channels.count)
                }
            } catch {
                await MainActor.run {
                    validationStatus = .invalid(error.localizedDescription)
                }
            }
        }
    }

    private func addDispatcharr() {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)) else {
            errorMessage = "Invalid URL"
            return
        }

        isAdding = true
        errorMessage = nil

        Task {
            await dataStore.addDispatcharrSource(
                baseURL: url,
                name: displayName.isEmpty ? "Live TV" : displayName
            )

            await dataStore.loadChannels()

            await MainActor.run {
                isAdding = false
                onComplete()
            }
        }
    }
}

// MARK: - M3U Config

struct M3UConfigView: View {
    let onComplete: () -> Void
    let onBack: () -> Void

    @StateObject private var dataStore = LiveTVDataStore.shared
    @State private var m3uURL = ""
    @State private var epgURL = ""
    @State private var displayName = "IPTV"
    @State private var isAdding = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    enum Field {
        case m3u, epg, name
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                // Back button
                HStack {
                    Button {
                        onBack()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.horizontal, 40)

                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.green.gradient)
                            .frame(width: 80, height: 80)

                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text("Add M3U Playlist")
                        .font(.system(size: 28, weight: .bold))
                }
                .padding(.top, 8)

                // Form
                VStack(spacing: 20) {
                    // M3U URL field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("M3U Playlist URL")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("http://example.com/playlist.m3u", text: $m3uURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                            .focused($focusedField, equals: .m3u)
                            .autocorrectionDisabled()
                            #if os(tvOS)
                            .keyboardType(.URL)
                            #endif

                        Text("URL to your M3U or M3U8 playlist file")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    // EPG URL field (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("EPG URL")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("(Optional)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary.opacity(0.7))
                        }

                        TextField("http://example.com/epg.xml", text: $epgURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                            .focused($focusedField, equals: .epg)
                            .autocorrectionDisabled()
                            #if os(tvOS)
                            .keyboardType(.URL)
                            #endif

                        Text("XMLTV format EPG for program guide data")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    // Display name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display Name")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("IPTV", text: $displayName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                            .focused($focusedField, equals: .name)
                    }
                }
                .padding(.horizontal, 40)

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 16))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                // Add button
                Button {
                    addM3U()
                } label: {
                    HStack(spacing: 10) {
                        if isAdding {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isAdding ? "Adding..." : "Add Source")
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(m3uURL.isEmpty ? Color.gray : Color.green)
                    )
                }
                .buttonStyle(.plain)
                .disabled(m3uURL.isEmpty || isAdding)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }

    private func addM3U() {
        guard let m3u = URL(string: m3uURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Invalid M3U URL"
            return
        }

        let epg: URL? = epgURL.isEmpty ? nil : URL(string: epgURL.trimmingCharacters(in: .whitespacesAndNewlines))

        isAdding = true
        errorMessage = nil

        Task {
            await dataStore.addM3USource(
                m3uURL: m3u,
                epgURL: epg,
                name: displayName.isEmpty ? "IPTV" : displayName
            )

            await dataStore.loadChannels()

            await MainActor.run {
                isAdding = false
                onComplete()
            }
        }
    }
}

#Preview {
    AddLiveTVSourceSheet()
}
