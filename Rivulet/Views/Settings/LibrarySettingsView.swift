//
//  LibrarySettingsView.swift
//  Rivulet
//
//  Library visibility and ordering settings
//

import SwiftUI

struct LibrarySettingsView: View {
    @StateObject private var dataStore = PlexDataStore.shared
    @StateObject private var librarySettings = LibrarySettingsManager.shared
    var goBack: () -> Void = {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                // Header (Menu button on remote navigates back)
                Text("Sidebar Libraries")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.top, 60)

                Text("Choose which libraries appear in the sidebar. Tap to toggle visibility, use arrows to reorder.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 80)

                if dataStore.libraries.isEmpty {
                    // No libraries
                    VStack(spacing: 28) {
                        Image(systemName: "folder")
                            .font(.system(size: 64, weight: .thin))
                            .foregroundStyle(Color(white: 0.5))

                        Text("No Libraries")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(Color(white: 0.1))

                        Text("Connect to a Plex server to manage library visibility.")
                            .font(.system(size: 19))
                            .foregroundStyle(Color(white: 0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.white.opacity(0.85))
                    )
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 80)
                } else {
                    // Library list
                    VStack(spacing: 24) {
                        SettingsSection(title: "Libraries") {
                            ForEach(orderedLibraries, id: \.key) { library in
                                LibraryVisibilityRow(
                                    library: library,
                                    isVisible: librarySettings.isLibraryVisible(library.key),
                                    onToggle: {
                                        librarySettings.toggleVisibility(for: library.key)
                                    },
                                    onMoveUp: canMoveUp(library) ? { moveUp(library) } : nil,
                                    onMoveDown: canMoveDown(library) ? { moveDown(library) } : nil
                                )
                            }
                        }

                        // Reset button
                        SettingsSection(title: "Reset") {
                            SettingsActionRow(
                                title: "Reset to Defaults",
                                isDestructive: false
                            ) {
                                librarySettings.resetToDefaults()
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
                }
            }
        }
        .background(Color.black)
    }

    // MARK: - Helpers

    /// Libraries sorted by user preference (for display in settings)
    private var orderedLibraries: [PlexLibrary] {
        librarySettings.sortLibraries(dataStore.libraries.filter { $0.isVideoLibrary })
    }

    private func canMoveUp(_ library: PlexLibrary) -> Bool {
        guard let index = orderedLibraries.firstIndex(where: { $0.key == library.key }) else {
            return false
        }
        return index > 0
    }

    private func canMoveDown(_ library: PlexLibrary) -> Bool {
        guard let index = orderedLibraries.firstIndex(where: { $0.key == library.key }) else {
            return false
        }
        return index < orderedLibraries.count - 1
    }

    private func moveUp(_ library: PlexLibrary) {
        guard let orderIndex = librarySettings.libraryOrder.firstIndex(of: library.key) else {
            return
        }
        if orderIndex > 0 {
            librarySettings.moveLibrary(from: orderIndex, to: orderIndex - 1)
        }
    }

    private func moveDown(_ library: PlexLibrary) {
        guard let orderIndex = librarySettings.libraryOrder.firstIndex(of: library.key) else {
            return
        }
        if orderIndex < librarySettings.libraryOrder.count - 1 {
            librarySettings.moveLibrary(from: orderIndex, to: orderIndex + 2)
        }
    }
}

// MARK: - Library Visibility Row

struct LibraryVisibilityRow: View {
    let library: PlexLibrary
    let isVisible: Bool
    let onToggle: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    @FocusState private var isFocused: Bool

    private var iconName: String {
        switch library.type {
        case "movie": return "film.fill"
        case "show": return "tv.fill"
        case "artist": return "music.note"
        case "photo": return "photo.fill"
        default: return "folder.fill"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Reorder controls (always visible, subtle)
            VStack(spacing: 4) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(white: onMoveUp != nil ? 0.35 : 0.6))
                    .onTapGesture {
                        onMoveUp?()
                    }

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(white: onMoveDown != nil ? 0.35 : 0.6))
                    .onTapGesture {
                        onMoveDown?()
                    }
            }
            .frame(width: 24)

            // Library icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isVisible ? Color.blue.gradient : Color.gray.opacity(0.5).gradient)
                    .frame(width: 52, height: 52)

                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Library info - dark colors for contrast on white glass background
            VStack(alignment: .leading, spacing: 3) {
                Text(library.title)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color(white: isVisible ? 0.1 : 0.4))

                Text(library.type.capitalized)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(white: 0.4))
            }

            Spacer()

            // On/Off indicator (Apple tvOS Settings style)
            Text(isVisible ? "On" : "Off")
                .font(.system(size: 19))
                .foregroundStyle(Color(white: 0.45))
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
            onToggle()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.2), value: isVisible)
    }
}

#Preview {
    LibrarySettingsView()
}
