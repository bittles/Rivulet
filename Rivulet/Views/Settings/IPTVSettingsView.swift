//
//  IPTVSettingsView.swift
//  Rivulet
//
//  Live TV source settings - manages Plex Live TV and M3U sources
//

import SwiftUI

struct IPTVSettingsView: View {
    @StateObject private var dataStore = LiveTVDataStore.shared
    @StateObject private var authManager = PlexAuthManager.shared
    @State private var showAddSourceSheet = false
    @State private var selectedSourceForDetail: LiveTVDataStore.LiveTVSourceInfo?
    var goBack: () -> Void = {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                Text("Live TV Sources")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.top, 60)

                Text("Add sources for Live TV channels. You can use Plex Live TV or any M3U playlist.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 80)

                VStack(spacing: 24) {
                    // Connected Sources
                    if !dataStore.sources.isEmpty {
                        SettingsSection(title: "Connected Sources") {
                            ForEach(dataStore.sources) { source in
                                LiveTVSourceRow(source: source) {
                                    selectedSourceForDetail = source
                                }
                            }
                        }
                    }

                    // Add Source Button
                    SettingsSection(title: dataStore.sources.isEmpty ? "Get Started" : "Add More") {
                        AddSourceButton {
                            showAddSourceSheet = true
                        }
                    }

                    // Plex Live TV availability hint
                    if authManager.isAuthenticated && !hasPlexLiveTVSource {
                        PlexLiveTVHintCard {
                            showAddSourceSheet = true
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .background(Color.black)
        .sheet(isPresented: $showAddSourceSheet) {
            AddLiveTVSourceSheet()
        }
        .sheet(item: $selectedSourceForDetail) { source in
            LiveTVSourceDetailSheet(source: source)
        }
    }

    private var hasPlexLiveTVSource: Bool {
        dataStore.sources.contains { $0.sourceType == .plex }
    }
}

// MARK: - Live TV Source Row

struct LiveTVSourceRow: View {
    let source: LiveTVDataStore.LiveTVSourceInfo
    let action: () -> Void

    @FocusState private var isFocused: Bool

    private var iconName: String {
        switch source.sourceType {
        case .plex: return "play.rectangle.fill"
        case .dispatcharr: return "antenna.radiowaves.left.and.right"
        case .genericM3U: return "list.bullet.rectangle"
        }
    }

    private var iconColor: Color {
        switch source.sourceType {
        case .plex: return .orange
        case .dispatcharr: return .blue
        case .genericM3U: return .green
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 52, height: 52)

                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Source info
            VStack(alignment: .leading, spacing: 4) {
                Text(source.displayName)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color(white: 0.1))

                HStack(spacing: 8) {
                    // Connection status
                    Circle()
                        .fill(source.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

                    Text(source.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.4))

                    if source.channelCount > 0 {
                        Text("•")
                            .foregroundStyle(Color(white: 0.4))
                        Text("\(source.channelCount) channels")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(white: 0.4))
                    }
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isFocused ? .black.opacity(0.1) : .clear)
        )
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            action()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Add Source Button

struct AddSourceButton: View {
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.gradient)
                    .frame(width: 52, height: 52)

                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Add Live TV Source")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color(white: 0.1))

                Text("Plex Live TV or M3U playlist")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(white: 0.4))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isFocused ? .black.opacity(0.1) : .clear)
        )
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            action()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Plex Live TV Hint Card

struct PlexLiveTVHintCard: View {
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "tv.and.mediabox")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Plex Live TV Available")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color(white: 0.1))

                    Text("Your Plex server may have Live TV. Add it as a source to access channels.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack {
                Spacer()
                Text("Add Plex Live TV")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.blue)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.85))
        )
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isFocused ? .blue.opacity(0.5) : .clear, lineWidth: 3)
        )
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            action()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

#Preview {
    IPTVSettingsView()
}
