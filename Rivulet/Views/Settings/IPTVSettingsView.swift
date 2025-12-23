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
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.top, 60)

                Text("Add sources for Live TV channels. You can use Plex Live TV or any M3U playlist.")
                    .font(.system(size: 24))
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
        HStack(spacing: 20) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 64, height: 64)

                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Source info
            VStack(alignment: .leading, spacing: 5) {
                Text(source.displayName)
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    // Connection status
                    Circle()
                        .fill(source.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)

                    Text(source.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 21))
                        .foregroundStyle(.white.opacity(0.6))

                    if source.channelCount > 0 {
                        Text("•")
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\(source.channelCount) channels")
                            .font(.system(size: 21))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isFocused ? .white.opacity(0.15) : .clear)
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
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blue.gradient)
                    .frame(width: 64, height: 64)

                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Add Live TV Source")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white)

                Text("Plex Live TV or M3U playlist")
                    .font(.system(size: 23))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isFocused ? .white.opacity(0.15) : .clear)
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
        VStack(spacing: 20) {
            HStack(spacing: 18) {
                Image(systemName: "tv.and.mediabox")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Plex Live TV Available")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Your Plex server may have Live TV. Add it as a source to access channels.")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack {
                Spacer()
                Text("Add Plex Live TV")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.blue)
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.blue)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isFocused ? .blue.opacity(0.5) : .clear, lineWidth: 3)
        )
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
