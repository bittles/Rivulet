//
//  MediaItemContextMenu.swift
//  Rivulet
//
//  Context menu for media items with common actions
//

import SwiftUI

// MARK: - Context Menu Source

/// Identifies where the context menu was triggered from
enum MediaItemContextSource {
    case continueWatching
    case library
    case other
}

// MARK: - Context Menu Actions

/// Callback type for context menu actions that may require data refresh
typealias MediaItemRefreshCallback = () async -> Void

// MARK: - Context Menu Modifier

/// A view modifier that adds a context menu to media items with common Plex actions
struct MediaItemContextMenu: ViewModifier {
    let item: PlexMetadata
    let serverURL: String
    let authToken: String
    let source: MediaItemContextSource
    var onRefreshNeeded: MediaItemRefreshCallback?

    @State private var isPerformingAction = false

    private let networkManager = PlexNetworkManager.shared

    func body(content: Content) -> some View {
        content.contextMenu {
            // Watch from Beginning
            Button {
                performAction {
                    try await networkManager.markUnwatched(
                        serverURL: serverURL,
                        authToken: authToken,
                        ratingKey: item.ratingKey ?? ""
                    )
                }
            } label: {
                Label("Watch from Beginning", systemImage: "play.fill")
            }

            Divider()

            // Mark as Watched
            if item.viewCount == nil || item.viewCount == 0 || item.watchProgress != nil {
                Button {
                    performAction {
                        try await networkManager.markWatched(
                            serverURL: serverURL,
                            authToken: authToken,
                            ratingKey: item.ratingKey ?? ""
                        )
                    }
                } label: {
                    Label("Mark as Watched", systemImage: "eye.fill")
                }
            }

            // Mark as Unwatched (only show if already watched)
            if let viewCount = item.viewCount, viewCount > 0 {
                Button {
                    performAction {
                        try await networkManager.markUnwatched(
                            serverURL: serverURL,
                            authToken: authToken,
                            ratingKey: item.ratingKey ?? ""
                        )
                    }
                } label: {
                    Label("Mark as Unwatched", systemImage: "eye.slash.fill")
                }
            }

            // Remove from Continue Watching (only in continue watching section)
            if source == .continueWatching {
                Button(role: .destructive) {
                    performAction {
                        try await networkManager.removeFromContinueWatching(
                            serverURL: serverURL,
                            authToken: authToken,
                            ratingKey: item.ratingKey ?? ""
                        )
                    }
                } label: {
                    Label("Remove from Continue Watching", systemImage: "xmark.circle.fill")
                }
            }

            Divider()

            // Refresh Metadata
            Button {
                performAction {
                    try await networkManager.refreshMetadata(
                        serverURL: serverURL,
                        authToken: authToken,
                        ratingKey: item.ratingKey ?? ""
                    )
                }
            } label: {
                Label("Refresh Metadata", systemImage: "arrow.clockwise")
            }
        }
    }

    private func performAction(_ action: @escaping () async throws -> Void) {
        guard !isPerformingAction else { return }
        isPerformingAction = true

        Task {
            do {
                try await action()
                await onRefreshNeeded?()
            } catch {
                print("Context menu action failed: \(error)")
            }
            isPerformingAction = false
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a context menu with common Plex media actions
    func mediaItemContextMenu(
        item: PlexMetadata,
        serverURL: String,
        authToken: String,
        source: MediaItemContextSource = .other,
        onRefreshNeeded: MediaItemRefreshCallback? = nil
    ) -> some View {
        modifier(MediaItemContextMenu(
            item: item,
            serverURL: serverURL,
            authToken: authToken,
            source: source,
            onRefreshNeeded: onRefreshNeeded
        ))
    }
}
