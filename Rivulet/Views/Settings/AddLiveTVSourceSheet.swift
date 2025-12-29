//
//  AddLiveTVSourceSheet.swift
//  Rivulet
//
//  Full-screen view for adding a new Live TV source (Plex or M3U)
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
            // Solid black background - no blur/material issues
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header bar
                headerBar

                if let sourceType = selectedSourceType {
                    // Configuration form for selected source type
                    configurationView(for: sourceType)
                } else {
                    // Source type picker
                    sourceTypePicker
                }
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button {
                if selectedSourceType != nil {
                    selectedSourceType = nil
                } else {
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selectedSourceType != nil ? "chevron.left" : "xmark")
                        .font(.system(size: 18, weight: .semibold))
                    Text(selectedSourceType != nil ? "Back" : "Cancel")
                        .font(.system(size: 24, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Text(headerTitle)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            // Invisible spacer for balance
            Text("Cancel")
                .font(.system(size: 24, weight: .medium))
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .opacity(0)
        }
        .padding(.horizontal, 60)
        .padding(.top, 40)
        .padding(.bottom, 24)
    }

    private var headerTitle: String {
        switch selectedSourceType {
        case .plex: return "Add Plex Live TV"
        case .dispatcharr: return "Add M3U Server"
        case .genericM3U: return "Add M3U Playlist"
        case nil: return "Add Live TV Source"
        }
    }

    // MARK: - Source Type Picker

    private var sourceTypePicker: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                Text("Choose a source type to add Live TV channels")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 16)

                VStack(spacing: 12) {
                    // Plex Live TV option (only if authenticated)
                    if authManager.isAuthenticated {
                        SourceTypeCard(
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
                    SourceTypeCard(
                        icon: "server.rack",
                        iconColor: .blue,
                        title: "M3U Server",
                        subtitle: "Server with M3U and EPG endpoints"
                    ) {
                        selectedSourceType = .dispatcharr
                    }

                    // Generic M3U option
                    SourceTypeCard(
                        icon: "list.bullet.rectangle",
                        iconColor: .green,
                        title: "M3U Playlist",
                        subtitle: "Add any M3U/M3U8 playlist URL"
                    ) {
                        selectedSourceType = .genericM3U
                    }
                }

                // Error message for Plex
                if let error = plexError {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.leading)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.yellow.opacity(0.1))
                    )
                    .padding(.top, 16)
                }

                // Plex not connected hint
                if !authManager.isAuthenticated {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.blue)
                        Text("Connect your Plex server in Settings to access Plex Live TV")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.blue.opacity(0.1))
                    )
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Configuration Views

    @ViewBuilder
    private func configurationView(for sourceType: LiveTVSourceType) -> some View {
        switch sourceType {
        case .plex:
            PlexLiveTVConfigForm(onComplete: { dismiss() })
        case .dispatcharr:
            DispatcharrConfigForm(onComplete: { dismiss() })
        case .genericM3U:
            M3UConfigForm(onComplete: { dismiss() })
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

// MARK: - Source Type Card

private struct SourceTypeCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var isLoading: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 24) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 72, height: 72)

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            // Text
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isFocused ? .white.opacity(0.2) : .white.opacity(0.08))
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
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

// MARK: - Plex Live TV Config Form

private struct PlexLiveTVConfigForm: View {
    let onComplete: () -> Void

    @StateObject private var authManager = PlexAuthManager.shared
    @StateObject private var dataStore = LiveTVDataStore.shared
    @State private var isAdding = false
    @State private var errorMessage: String?

    @FocusState private var addButtonFocused: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 40) {
                // Icon and info
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(.orange.gradient)
                            .frame(width: 120, height: 120)

                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 10) {
                        if let serverName = authManager.savedServerName {
                            Text(serverName)
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        Text("Live TV channels from your Plex server will be added. You can watch live channels and see the program guide.")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 600)
                    }
                }
                .padding(.top, 40)

                // Error message
                if let error = errorMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.red)
                    }
                    .font(.system(size: 20))
                }

                // Add button
                Button {
                    addPlexLiveTV()
                } label: {
                    HStack(spacing: 12) {
                        if isAdding {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isAdding ? "Adding..." : "Add Plex Live TV")
                            .font(.system(size: 26, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(minWidth: 280)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(addButtonFocused ? .orange : .orange.opacity(0.85))
                    )
                    .scaleEffect(addButtonFocused ? 1.05 : 1.0)
                }
                .buttonStyle(.plain)
                .focused($addButtonFocused)
                .disabled(isAdding)
                .animation(.easeOut(duration: 0.15), value: addButtonFocused)

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 80)
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
            await dataStore.loadChannels()

            await MainActor.run {
                isAdding = false
                onComplete()
            }
        }
    }
}

// MARK: - M3U Server Config Form

private struct DispatcharrConfigForm: View {
    let onComplete: () -> Void

    @StateObject private var dataStore = LiveTVDataStore.shared
    @State private var serverURL = ""
    @State private var displayName = "Live TV"
    @State private var isAdding = false
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var validationStatus: ValidationStatus = .idle

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case url, name, validate, add
    }

    enum ValidationStatus: Equatable {
        case idle
        case validating
        case valid(channelCount: Int)
        case invalid(String)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 32) {
                // Form fields
                VStack(spacing: 24) {
                    // Server URL field
                    TVTextField(
                        label: "Server URL",
                        placeholder: "http://192.168.1.100:9191",
                        text: $serverURL,
                        hint: "Base URL of your M3U server (expects /output/m3u and /output/epg)",
                        isFocused: focusedField == .url
                    )
                    .focused($focusedField, equals: .url)

                    // Display name field
                    TVTextField(
                        label: "Display Name",
                        placeholder: "Live TV",
                        text: $displayName,
                        isFocused: focusedField == .name
                    )
                    .focused($focusedField, equals: .name)

                    // Validation status
                    if validationStatus != .idle {
                        validationStatusView
                    }

                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                        }
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Buttons
                HStack(spacing: 20) {
                    // Validate button
                    Button {
                        validateServer()
                    } label: {
                        HStack(spacing: 10) {
                            if isValidating {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isValidating ? "Checking..." : "Validate")
                                .font(.system(size: 24, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(focusedField == .validate ? .white.opacity(0.25) : .white.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                    .focused($focusedField, equals: .validate)
                    .disabled(serverURL.isEmpty || isValidating)

                    // Add button
                    Button {
                        addDispatcharr()
                    } label: {
                        HStack(spacing: 10) {
                            if isAdding {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isAdding ? "Adding..." : "Add Source")
                                .font(.system(size: 24, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(canAdd ? (focusedField == .add ? .blue : .blue.opacity(0.85)) : .gray.opacity(0.5))
                        )
                        .scaleEffect(focusedField == .add && canAdd ? 1.03 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedField, equals: .add)
                    .disabled(!canAdd || isAdding)
                }
                .animation(.easeOut(duration: 0.15), value: focusedField)

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 80)
            .padding(.top, 24)
        }
        .onAppear {
            focusedField = .url
        }
    }

    @ViewBuilder
    private var validationStatusView: some View {
        HStack(spacing: 12) {
            switch validationStatus {
            case .idle:
                EmptyView()
            case .validating:
                ProgressView()
                Text("Checking server...")
                    .foregroundStyle(.white.opacity(0.6))
            case .valid(let count):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Connected! Found \(count) channels")
                    .foregroundStyle(.green)
            case .invalid(let message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var canAdd: Bool {
        !serverURL.isEmpty && !displayName.isEmpty
    }

    private func validateServer() {
        guard let service = DispatcharrService.create(from: serverURL) else {
            validationStatus = .invalid("Invalid URL format")
            return
        }

        validationStatus = .validating
        isValidating = true

        Task {
            do {
                let channels = try await service.fetchChannels()
                await MainActor.run {
                    validationStatus = .valid(channelCount: channels.count)
                    isValidating = false
                }
            } catch {
                await MainActor.run {
                    validationStatus = .invalid(error.localizedDescription)
                    isValidating = false
                }
            }
        }
    }

    private func addDispatcharr() {
        // Use the same URL normalization as DispatcharrService.create()
        var cleanedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove trailing slash
        if cleanedURL.hasSuffix("/") {
            cleanedURL = String(cleanedURL.dropLast())
        }

        // Add http:// if no scheme
        if !cleanedURL.hasPrefix("http://") && !cleanedURL.hasPrefix("https://") {
            cleanedURL = "http://" + cleanedURL
        }

        guard let url = URL(string: cleanedURL) else {
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

// MARK: - M3U Playlist Config Form

private struct M3UConfigForm: View {
    let onComplete: () -> Void

    @StateObject private var dataStore = LiveTVDataStore.shared
    @State private var m3uURL = ""
    @State private var epgURL = ""
    @State private var displayName = "IPTV"
    @State private var isAdding = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case m3u, epg, name, add
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 32) {
                // Form fields
                VStack(spacing: 24) {
                    // M3U URL field
                    TVTextField(
                        label: "M3U Playlist URL",
                        placeholder: "http://example.com/playlist.m3u",
                        text: $m3uURL,
                        hint: "URL to your M3U or M3U8 playlist file",
                        isFocused: focusedField == .m3u
                    )
                    .focused($focusedField, equals: .m3u)

                    // EPG URL field (optional)
                    TVTextField(
                        label: "EPG URL (Optional)",
                        placeholder: "http://example.com/epg.xml",
                        text: $epgURL,
                        hint: "XMLTV format EPG for program guide data",
                        isFocused: focusedField == .epg
                    )
                    .focused($focusedField, equals: .epg)

                    // Display name field
                    TVTextField(
                        label: "Display Name",
                        placeholder: "IPTV",
                        text: $displayName,
                        isFocused: focusedField == .name
                    )
                    .focused($focusedField, equals: .name)

                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                        }
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Add button
                Button {
                    addM3U()
                } label: {
                    HStack(spacing: 12) {
                        if isAdding {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isAdding ? "Adding..." : "Add Source")
                            .font(.system(size: 24, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(minWidth: 200)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(m3uURL.isEmpty ? .gray.opacity(0.5) : (focusedField == .add ? .green : .green.opacity(0.85)))
                    )
                    .scaleEffect(focusedField == .add && !m3uURL.isEmpty ? 1.03 : 1.0)
                }
                .buttonStyle(.plain)
                .focused($focusedField, equals: .add)
                .disabled(m3uURL.isEmpty || isAdding)
                .animation(.easeOut(duration: 0.15), value: focusedField)

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 80)
            .padding(.top, 24)
        }
        .onAppear {
            focusedField = .m3u
        }
    }

    private func addM3U() {
        // Normalize M3U URL
        var cleanedM3U = m3uURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedM3U.hasPrefix("http://") && !cleanedM3U.hasPrefix("https://") {
            cleanedM3U = "http://" + cleanedM3U
        }

        guard let m3u = URL(string: cleanedM3U) else {
            errorMessage = "Invalid M3U URL"
            return
        }

        // Normalize EPG URL if provided
        var epg: URL? = nil
        if !epgURL.isEmpty {
            var cleanedEPG = epgURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedEPG.hasPrefix("http://") && !cleanedEPG.hasPrefix("https://") {
                cleanedEPG = "http://" + cleanedEPG
            }
            epg = URL(string: cleanedEPG)
        }

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

// MARK: - TV Text Field

private struct TVTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var hint: String? = nil
    var isFocused: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isFocused ? Color(white: 0.25) : Color(white: 0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isFocused ? .blue : .clear, lineWidth: 3)
                )
                .autocorrectionDisabled()
                #if os(tvOS)
                .keyboardType(.URL)
                #endif

            if let hint = hint {
                Text(hint)
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

#Preview {
    AddLiveTVSourceSheet()
}
