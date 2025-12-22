//
//  LiveTVSourceDetailSheet.swift
//  Rivulet
//
//  Detail view for managing an individual Live TV source
//

import SwiftUI

struct LiveTVSourceDetailSheet: View {
    let source: LiveTVDataStore.LiveTVSourceInfo

    @Environment(\.dismiss) private var dismiss
    @StateObject private var dataStore = LiveTVDataStore.shared
    @State private var isRefreshing = false
    @State private var showDeleteConfirmation = false

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

    private var sourceTypeLabel: String {
        switch source.sourceType {
        case .plex: return "Plex Live TV"
        case .dispatcharr: return "Dispatcharr"
        case .genericM3U: return "M3U Playlist"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("Source Details")
                        .font(.system(size: 28, weight: .bold))

                    Spacer()

                    // Invisible spacer for alignment
                    Button("Done") { }
                        .buttonStyle(.bordered)
                        .opacity(0)
                }
                .padding(.horizontal, 40)
                .padding(.top, 32)
                .padding(.bottom, 24)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 32) {
                        // Source icon and name
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(iconColor.gradient)
                                    .frame(width: 100, height: 100)

                                Image(systemName: iconName)
                                    .font(.system(size: 44, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            VStack(spacing: 6) {
                                Text(source.displayName)
                                    .font(.system(size: 32, weight: .bold))

                                Text(sourceTypeLabel)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Status card
                        VStack(spacing: 0) {
                            statusRow(title: "Status", value: source.isConnected ? "Connected" : "Disconnected", valueColor: source.isConnected ? .green : .red)
                            Divider().padding(.horizontal, 16)
                            statusRow(title: "Channels", value: "\(source.channelCount)")
                            if let lastSync = source.lastSync {
                                Divider().padding(.horizontal, 16)
                                statusRow(title: "Last Synced", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .padding(.horizontal, 40)

                        // Actions
                        VStack(spacing: 12) {
                            // Refresh button
                            ActionButton(
                                icon: "arrow.clockwise",
                                title: "Refresh Channels",
                                subtitle: "Reload channel list from source",
                                isLoading: isRefreshing
                            ) {
                                refreshSource()
                            }

                            // Remove button
                            ActionButton(
                                icon: "trash",
                                title: "Remove Source",
                                subtitle: "Disconnect this Live TV source",
                                isDestructive: true
                            ) {
                                showDeleteConfirmation = true
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    }
                }
            }
            .frame(maxWidth: 700)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(40)

            // Delete confirmation overlay
            if showDeleteConfirmation {
                deleteConfirmationOverlay
            }
        }
    }

    private func statusRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var deleteConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                VStack(spacing: 8) {
                    Text("Remove Source?")
                        .font(.system(size: 28, weight: .bold))

                    Text("This will remove \"\(source.displayName)\" and all its channels from Live TV.")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                HStack(spacing: 16) {
                    Button("Cancel") {
                        showDeleteConfirmation = false
                    }
                    .buttonStyle(.bordered)

                    Button {
                        removeSource()
                    } label: {
                        Text("Remove")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.red)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThickMaterial)
            )
        }
    }

    private func refreshSource() {
        isRefreshing = true

        Task {
            await dataStore.refreshChannels()

            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    private func removeSource() {
        Task {
            await dataStore.removeSource(id: source.id)

            await MainActor.run {
                dismiss()
            }
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    var isLoading: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDestructive ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 52, height: 52)

                if isLoading {
                    ProgressView()
                        .tint(isDestructive ? .red : .blue)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isDestructive ? .red : .blue)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(isDestructive ? .red : .primary)

                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isFocused ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
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

#Preview {
    LiveTVSourceDetailSheet(source: LiveTVDataStore.LiveTVSourceInfo(
        id: "test",
        sourceType: .dispatcharr,
        displayName: "Test Source",
        channelCount: 42,
        isConnected: true,
        lastSync: Date()
    ))
}
