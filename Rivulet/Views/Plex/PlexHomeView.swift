//
//  PlexHomeView.swift
//  Rivulet
//
//  Home screen for Plex with Continue Watching and Recently Added
//

import SwiftUI
import Combine

struct PlexHomeView: View {
    @StateObject private var dataStore = PlexDataStore.shared
    @StateObject private var authManager = PlexAuthManager.shared
    @AppStorage("showHomeHero") private var showHomeHero = true
    @Environment(\.contentFocusVersion) private var contentFocusVersion
    @State private var selectedItem: PlexMetadata?
    @State private var heroItem: PlexMetadata?
    @State private var focusTrigger = 0  // Increment to trigger first row focus

    // MARK: - Computed Hubs (merged Continue Watching + On Deck)

    /// Processes hubs to combine Continue Watching and On Deck into a single row
    private var processedHubs: [PlexHub] {
        var result: [PlexHub] = []
        var continueWatchingItems: [PlexMetadata] = []
        var seenRatingKeys: Set<String> = []

        for hub in dataStore.hubs {
            let identifier = hub.hubIdentifier?.lowercased() ?? ""
            let title = hub.title?.lowercased() ?? ""

            // Check if this is a Continue Watching or On Deck hub
            let isContinueWatching = identifier.contains("continuewatching") ||
                                     title.contains("continue watching")
            let isOnDeck = identifier.contains("ondeck") ||
                          title.contains("on deck")

            if isContinueWatching || isOnDeck {
                // Merge items, deduplicating by ratingKey
                if let items = hub.Metadata {
                    for item in items {
                        if let key = item.ratingKey, !seenRatingKeys.contains(key) {
                            seenRatingKeys.insert(key)
                            continueWatchingItems.append(item)
                        }
                    }
                }
            } else {
                // Keep other hubs as-is
                result.append(hub)
            }
        }

        // Sort merged items by lastViewedAt (most recent first)
        continueWatchingItems.sort { item1, item2 in
            let time1 = item1.lastViewedAt ?? 0
            let time2 = item2.lastViewedAt ?? 0
            return time1 > time2
        }

        // Create merged Continue Watching hub if we have items
        if !continueWatchingItems.isEmpty {
            var mergedHub = PlexHub()
            mergedHub.hubIdentifier = "continueWatching"
            mergedHub.title = "Continue Watching"
            mergedHub.Metadata = continueWatchingItems
            // Insert at beginning
            result.insert(mergedHub, at: 0)
        }

        return result
    }

    var body: some View {
        ZStack {
            if !authManager.isAuthenticated {
                notConnectedView
            } else if dataStore.isLoadingHubs && dataStore.hubs.isEmpty {
                loadingView
            } else if let error = dataStore.hubsError, dataStore.hubs.isEmpty {
                errorView(error)
            } else if dataStore.hubs.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .refreshable {
            await dataStore.refreshHubs()
        }
        .onAppear {
            selectHeroItem()
        }
        .onChange(of: dataStore.hubs.count) { _, _ in
            selectHeroItem()
        }
    }

    // MARK: - Hero Selection

    private func selectHeroItem() {
        // Pick a random item from recently added for the hero
        guard heroItem == nil else { return }
        let recentlyAdded = dataStore.hubs.first { hub in
            hub.hubIdentifier?.contains("recentlyAdded") == true ||
            hub.title?.lowercased().contains("recently added") == true
        }
        if let items = recentlyAdded?.Metadata, !items.isEmpty {
            heroItem = items.randomElement()
        } else if let firstHub = dataStore.hubs.first,
                  let items = firstHub.Metadata, !items.isEmpty {
            heroItem = items.first
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Hero section (if enabled)
                if showHomeHero, let hero = heroItem {
                    HeroView(
                        item: hero,
                        serverURL: authManager.selectedServerURL ?? "",
                        authToken: authManager.authToken ?? ""
                    ) {
                        selectedItem = hero
                    }
                }

                // Content rows (uses processedHubs which merges Continue Watching + On Deck)
                VStack(alignment: .leading, spacing: 48) {
                    ForEach(Array(processedHubs.enumerated()), id: \.element.id) { index, hub in
                        if let items = hub.Metadata, !items.isEmpty {
                            InfiniteContentRow(
                                title: hub.title ?? "Unknown",
                                initialItems: items,
                                hubKey: hub.key ?? hub.hubKey,
                                serverURL: authManager.selectedServerURL ?? "",
                                authToken: authManager.authToken ?? "",
                                onItemSelected: { item in
                                    selectedItem = item
                                },
                                focusTrigger: index == 0 ? focusTrigger : nil  // First row gets focus trigger
                            )
                        }
                    }
                }
                .padding(.top, 48)
                .padding(.bottom, 80)
            }
        }
        #if os(tvOS)
        .ignoresSafeArea(edges: .top)
        #endif
        .onChange(of: contentFocusVersion) { _, _ in
            // Trigger first row to claim focus when sidebar closes
            focusTrigger += 1
        }
        .sheet(item: $selectedItem) { item in
            PlexDetailView(item: item)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Unable to Load")
                .font(.title2)
                .fontWeight(.medium)

            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button {
                Task { await dataStore.refreshHubs() }
            } label: {
                Text("Try Again")
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "film.stack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("No Content")
                .font(.title2)
                .fontWeight(.medium)

            Text("Your Plex library appears to be empty.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                Task { await dataStore.refreshHubs() }
            } label: {
                Text("Refresh")
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Not Connected View

    private var notConnectedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "server.rack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Not Connected")
                .font(.title2)
                .fontWeight(.medium)

            Text("Connect to your Plex server in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Hero View

struct HeroView: View {
    let item: PlexMetadata
    let serverURL: String
    let authToken: String
    let onSelect: () -> Void

    @Environment(\.isFocused) private var isFocused

    private var artURL: URL? {
        // Prefer art (backdrop) over thumb (poster)
        let path = item.art ?? item.thumb
        guard let path else { return nil }
        var urlString = "\(serverURL)\(path)"
        if !urlString.contains("X-Plex-Token") {
            urlString += urlString.contains("?") ? "&" : "?"
            urlString += "X-Plex-Token=\(authToken)"
        }
        return URL(string: urlString)
    }

    var body: some View {
        Button(action: onSelect) {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    // Background art
                    AsyncImage(url: artURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        default:
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(white: 0.15), Color(white: 0.08)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }

                    // Gradient overlay for text legibility
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.3),
                            .black.opacity(0.85)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Content info
                    VStack(alignment: .leading, spacing: 12) {
                        // Type badge
                        if let type = item.type {
                            Text(type.uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        // Title
                        Text(item.title ?? "")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        // Metadata row
                        HStack(spacing: 16) {
                            if let year = item.year {
                                Text(String(year))
                            }
                            if let rating = item.contentRating {
                                Text(rating)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            if let duration = item.duration {
                                Text(formatDuration(duration))
                            }
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                        // Summary (truncated)
                        if let summary = item.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(2)
                                .frame(maxWidth: 700, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 60)
                }
            }
            #if os(tvOS)
            .frame(height: 600)
            #else
            .frame(height: 400)
            #endif
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .scaleEffect(isFocused ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isFocused)
        #endif
    }

    private func formatDuration(_ ms: Int) -> String {
        let minutes = ms / 60000
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

// MARK: - Content Row (replaces MediaRow for Home)

struct ContentRow: View {
    let title: String
    let items: [PlexMetadata]
    let serverURL: String
    let authToken: String
    var onItemSelected: ((PlexMetadata) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section title
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 80)

            // Horizontal scroll of posters
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(items, id: \.ratingKey) { item in
                        Button {
                            onItemSelected?(item)
                        } label: {
                            MediaPosterCard(
                                item: item,
                                serverURL: serverURL,
                                authToken: authToken
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 80)
            }
        }
    }
}

// MARK: - Infinite Content Row (with endless scrolling)

/// A content row that loads more items as the user scrolls near the end
struct InfiniteContentRow: View {
    let title: String
    let initialItems: [PlexMetadata]
    let hubKey: String?  // The hub's key for fetching more items
    let serverURL: String
    let authToken: String
    var onItemSelected: ((PlexMetadata) -> Void)?
    var focusTrigger: Int? = nil  // When non-nil and changes, focus first item

    @Environment(\.openSidebar) private var openSidebar
    @FocusState private var focusedIndex: Int?

    @State private var items: [PlexMetadata] = []
    @State private var isLoadingMore = false
    @State private var hasReachedEnd = false
    @State private var totalSize: Int?

    private let networkManager = PlexNetworkManager.shared
    private let pageSize = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section title with item count
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                if let total = totalSize, total > items.count {
                    Text("\(items.count) of \(total)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                } else if hasReachedEnd && items.count > pageSize {
                    Text("All \(items.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 80)

            // Horizontal scroll of posters with infinite loading
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(Array(items.enumerated()), id: \.element.ratingKey) { index, item in
                        Button {
                            onItemSelected?(item)
                        } label: {
                            MediaPosterCard(
                                item: item,
                                serverURL: serverURL,
                                authToken: authToken
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedIndex, equals: index)
                        .onMoveCommand { direction in
                            if direction == .left && index == 0 {
                                // Left arrow pressed on first item - open sidebar
                                print("🟢 [DEBUG] InfiniteContentRow: Left pressed on first item, opening sidebar")
                                openSidebar()
                            }
                        }
                        .onAppear {
                            // Load more when user is 5 items from the end
                            if index >= items.count - 5 {
                                Task {
                                    await loadMoreIfNeeded()
                                }
                            }
                        }
                    }

                    // Loading indicator at the end
                    if isLoadingMore {
                        loadingIndicator
                    } else if hasReachedEnd && items.count > pageSize {
                        endIndicator
                    }
                }
                .padding(.horizontal, 80)
            }
            // Removed .focusSection() to allow focus to escape to LeftEdgeTrigger when at leftmost position
        }
        .onAppear {
            if items.isEmpty {
                items = initialItems
                // Check if we already have all items
                if let size = totalSize, items.count >= size {
                    hasReachedEnd = true
                }
            }
        }
        .onChange(of: initialItems.count) { _, newCount in
            // Reset when initial items change (e.g., on refresh)
            if newCount != items.count || items.isEmpty {
                items = initialItems
                hasReachedEnd = false
            }
        }
        .onChange(of: focusTrigger) { _, newValue in
            // Focus first item when trigger changes (sidebar closed)
            if newValue != nil {
                focusedIndex = 0
            }
        }
    }

    private var loadingIndicator: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white.opacity(0.5))
        }
        .frame(width: 100, height: 150)
    }

    private var endIndicator: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.3))
            Text("All loaded")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(width: 100, height: 150)
    }

    private func loadMoreIfNeeded() async {
        // Don't load if we're already loading, reached the end, or have no hub key
        guard !isLoadingMore,
              !hasReachedEnd,
              let hubKey = hubKey,
              !hubKey.isEmpty else {
            return
        }

        // Check if we might have more items based on totalSize
        if let total = totalSize, items.count >= total {
            hasReachedEnd = true
            return
        }

        isLoadingMore = true

        do {
            let result = try await networkManager.getHubItems(
                serverURL: serverURL,
                authToken: authToken,
                hubKey: hubKey,
                start: items.count,
                count: pageSize
            )

            // Update total size if we got it
            if let size = result.totalSize {
                totalSize = size
            }

            if result.items.isEmpty {
                // No more items
                hasReachedEnd = true
            } else {
                // Append new items, deduplicating by ratingKey
                let existingKeys = Set(items.compactMap { $0.ratingKey })
                let newItems = result.items.filter { item in
                    guard let key = item.ratingKey else { return false }
                    return !existingKeys.contains(key)
                }

                if newItems.isEmpty {
                    // All items were duplicates, we've reached the end
                    hasReachedEnd = true
                } else {
                    items.append(contentsOf: newItems)

                    // Check if we've loaded everything
                    if let total = totalSize, items.count >= total {
                        hasReachedEnd = true
                    }
                }
            }

            print("InfiniteContentRow: Loaded \(result.items.count) more items for '\(title)', total: \(items.count), hasMore: \(!hasReachedEnd)")
        } catch {
            print("InfiniteContentRow: Failed to load more items: \(error)")
            // Don't mark as reached end on error - user can retry by scrolling
        }

        isLoadingMore = false
    }
}

#Preview {
    PlexHomeView()
        .preferredColorScheme(.dark)
}
