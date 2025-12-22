//
//  PlexLibraryView.swift
//  Rivulet
//
//  Grid view for browsing a Plex library section
//

import SwiftUI

struct PlexLibraryView: View {
    let libraryKey: String
    let libraryTitle: String

    @Environment(\.contentFocusVersion) private var contentFocusVersion
    
    @StateObject private var authManager = PlexAuthManager.shared
    @AppStorage("showLibraryHero") private var showLibraryHero = true
    @AppStorage("showLibraryRecommendations") private var showLibraryRecommendations = true
    @State private var items: [PlexMetadata] = []
    @State private var hubs: [PlexHub] = []  // Library-specific hubs from Plex API
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedItem: PlexMetadata?
    @State private var heroItem: PlexMetadata?
    @State private var focusTrigger = 0  // Increment to trigger first row focus

    private let networkManager = PlexNetworkManager.shared
    private let cacheManager = CacheManager.shared

    #if os(tvOS)
    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 32)
    ]
    #else
    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 200), spacing: 20)
    ]
    #endif

    // MARK: - Processed Hubs (merged Continue Watching + On Deck)

    /// Essential hub types that are always shown
    private func isEssentialHub(_ hub: PlexHub) -> Bool {
        let identifier = hub.hubIdentifier?.lowercased() ?? ""
        let title = hub.title?.lowercased() ?? ""

        // Continue Watching / On Deck
        if identifier.contains("continuewatching") || title.contains("continue watching") ||
           identifier.contains("ondeck") || title.contains("on deck") {
            return true
        }

        // Recently Added
        if identifier.contains("recentlyadded") || title.contains("recently added") {
            return true
        }

        // Recently Released (by year)
        if identifier.contains("recentlyreleased") || title.contains("recently released") ||
           identifier.contains("newestreleases") || title.contains("newest releases") {
            return true
        }

        return false
    }

    /// Processes hubs to combine Continue Watching and On Deck, similar to PlexHomeView
    private var processedHubs: [PlexHub] {
        var result: [PlexHub] = []
        var continueWatchingItems: [PlexMetadata] = []
        var seenRatingKeys: Set<String> = []

        for hub in hubs {
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
                // Filter: always show essential hubs, others only if setting enabled
                let isEssential = isEssentialHub(hub)
                if isEssential || showLibraryRecommendations {
                    result.append(hub)
                }
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
            let mergedHub = PlexHub(
                hubIdentifier: "continueWatching",
                title: "Continue Watching",
                Metadata: continueWatchingItems
            )
            // Insert at beginning
            result.insert(mergedHub, at: 0)
        }

        return result
    }

    var body: some View {
        ZStack {
            if !authManager.isAuthenticated {
                notConnectedView
            } else if isLoading && items.isEmpty {
                loadingView
            } else if let error = error, items.isEmpty {
                errorView(error)
            } else if items.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .task(id: libraryKey) {
            // Reset state when library key changes for instant switching
            error = nil
            heroItem = nil  // Reset hero so it can be reselected for new library
            
            if authManager.isAuthenticated {
                // Load items (will show cached data immediately and select hero)
                await loadItems()
            } else {
                // Not authenticated - clear everything
                items = []
                hubs = []
            }
        }
        .refreshable {
            await refresh()
        }
        .sheet(item: $selectedItem) { item in
            PlexDetailView(item: item)
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Hero section (if enabled)
                if showLibraryHero, let hero = heroItem {
                    HeroView(
                        item: hero,
                        serverURL: authManager.selectedServerURL ?? "",
                        authToken: authManager.authToken ?? ""
                    ) {
                        selectedItem = hero
                    }
                    .id("hero-\(libraryKey)-\(hero.ratingKey ?? "")")  // Force instant update when hero changes
                    .transaction { transaction in
                        // Disable animation for instant hero update
                        transaction.animation = nil
                    }
                }

                // Curated rows section (from Plex library hubs API)
                if showLibraryRecommendations && !processedHubs.isEmpty {
                    VStack(alignment: .leading, spacing: 48) {
                        ForEach(Array(processedHubs.enumerated()), id: \.element.id) { index, hub in
                            if let hubItems = hub.Metadata, !hubItems.isEmpty {
                                InfiniteContentRow(
                                    title: hub.title ?? "Unknown",
                                    initialItems: hubItems,
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
                }

                // Library section header
                librarySectionHeader

                // Full library grid
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach(items, id: \.ratingKey) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            MediaPosterCard(
                                item: item,
                                serverURL: authManager.selectedServerURL ?? "",
                                authToken: authManager.authToken ?? ""
                            )
                        }
                        #if os(tvOS)
                        .buttonStyle(CardButtonStyle())
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                #if os(tvOS)
                .padding(.horizontal, 80)
                .padding(.vertical, 28)  // Room for scale effect and shadow
                .padding(.bottom, 60)
                #else
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                #endif
            }
        }
        #if os(tvOS)
        .ignoresSafeArea(edges: .top)
        #endif
        .onAppear {
            // Hero will be selected when items load via task handler
            if heroItem == nil && !items.isEmpty {
                selectHeroItem()
            }
        }
        .onChange(of: items.count) { _, _ in
            // Reselect hero when items change (e.g., after background refresh)
            if heroItem == nil {
                selectHeroItem()
            }
        }
        .onChange(of: hubs.count) { _, _ in
            // Reselect hero when hubs load (they might have better hero candidates)
            selectHeroItem()
        }
        .onChange(of: contentFocusVersion) { _, _ in
            // Trigger first row to claim focus when sidebar closes
            focusTrigger += 1
        }
    }

    // MARK: - Hero Selection

    private func selectHeroItem() {
        // Always reselect hero when called (removed guard to allow updates)
        // This ensures hero updates immediately when switching libraries

        // Try to get hero from recently added hub first
        let recentlyAddedHub = hubs.first { hub in
            let identifier = hub.hubIdentifier?.lowercased() ?? ""
            let title = hub.title?.lowercased() ?? ""
            return identifier.contains("recentlyadded") || title.contains("recently added")
        }

        if let hubItems = recentlyAddedHub?.Metadata, !hubItems.isEmpty {
            heroItem = hubItems.randomElement()
            return
        }

        // Fallback to items sorted by addedAt
        if !items.isEmpty {
            let recentItems = items.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }.prefix(10)
            heroItem = recentItems.randomElement() ?? items.first
        }
    }

    private var librarySectionHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(libraryTitle)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .id("library-title-\(libraryKey)")  // Force instant update when library changes
                .transaction { transaction in
                    // Disable animation for instant title update
                    transaction.animation = nil
                }

            Text("\(items.count) items")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        #if os(tvOS)
        .padding(.horizontal, 80)
        .padding(.top, 60)
        .padding(.bottom, 32)
        #else
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .padding(.bottom, 24)
        #endif
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
                Task { await refresh() }
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

            Text("This library appears to be empty.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                Task { await refresh() }
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

    // MARK: - Data Loading

    private func loadItems() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else {
            error = "Not authenticated"
            items = []
            hubs = []
            return
        }

        // Try cache first - this is instant from memory/disk
        let cachedItems = await getCachedItems()
        if !cachedItems.isEmpty {
            // Show cached data immediately (no loading state)
            items = cachedItems
            // Select hero immediately from cached items
            selectHeroItemFromCurrentData()

            // Refresh in background silently (both items and hubs)
            async let itemsFetch: () = fetchFromServer(serverURL: serverURL, token: token)
            async let hubsFetch: () = fetchLibraryHubs(serverURL: serverURL, token: token)
            _ = await (itemsFetch, hubsFetch)
            // Reselect hero after hubs load (in case hubs have better hero candidates)
            selectHeroItem()
            return
        }

        // No cache - show loading and fetch both
        items = []
        hubs = []
        isLoading = true
        async let itemsFetch: () = fetchFromServer(serverURL: serverURL, token: token)
        async let hubsFetch: () = fetchLibraryHubs(serverURL: serverURL, token: token)
        _ = await (itemsFetch, hubsFetch)
        // Select hero after data loads
        selectHeroItem()
    }
    
    /// Select hero from currently loaded items/hubs (for instant display)
    private func selectHeroItemFromCurrentData() {
        // When switching libraries, hubs might not be loaded yet, so prioritize items
        // Try items first (they're available immediately from cache)
        if !items.isEmpty {
            let recentItems = items.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }.prefix(10)
            heroItem = recentItems.randomElement() ?? items.first
            return
        }
        
        // Fallback to hubs if items are empty but hubs are available
        if !hubs.isEmpty {
            let recentlyAddedHub = hubs.first { hub in
                let identifier = hub.hubIdentifier?.lowercased() ?? ""
                let title = hub.title?.lowercased() ?? ""
                return identifier.contains("recentlyadded") || title.contains("recently added")
            }
            
            if let hubItems = recentlyAddedHub?.Metadata, !hubItems.isEmpty {
                heroItem = hubItems.randomElement()
            }
        }
    }

    private func getCachedItems() async -> [PlexMetadata] {
        // Determine type based on library (this is simplified - ideally we'd know the library type)
        if let cached = await cacheManager.getCachedMovies(forLibrary: libraryKey) {
            return cached
        }
        if let cached = await cacheManager.getCachedShows(forLibrary: libraryKey) {
            return cached
        }
        return []
    }

    private func fetchFromServer(serverURL: String, token: String) async {
        do {
            let fetchedItems = try await networkManager.getLibraryItems(
                serverURL: serverURL,
                authToken: token,
                sectionId: libraryKey
            )
            items = fetchedItems

            // Cache based on type
            if let firstItem = fetchedItems.first {
                if firstItem.type == "movie" {
                    await cacheManager.cacheMovies(fetchedItems, forLibrary: libraryKey)
                } else if firstItem.type == "show" {
                    await cacheManager.cacheShows(fetchedItems, forLibrary: libraryKey)
                }
            }

            error = nil
        } catch {
            // Ignore cancellation errors - they happen when views are recreated
            if (error as NSError).code == NSURLErrorCancelled {
                print("PlexLibraryView: Request cancelled (view recreated)")
                isLoading = false
                return
            }
            if items.isEmpty {
                self.error = error.localizedDescription
            }
            print("PlexLibraryView: Failed to fetch items: \(error)")
        }
        isLoading = false
    }

    private func fetchLibraryHubs(serverURL: String, token: String) async {
        do {
            let fetchedHubs = try await networkManager.getLibraryHubs(
                serverURL: serverURL,
                authToken: token,
                sectionId: libraryKey
            )
            hubs = fetchedHubs
            print("PlexLibraryView: Loaded \(fetchedHubs.count) hubs for library \(libraryKey)")
            for hub in fetchedHubs {
                print("  - Hub: \(hub.title ?? "unknown") (\(hub.hubIdentifier ?? "no id")) with \(hub.Metadata?.count ?? 0) items")
            }
        } catch {
            // Ignore cancellation errors
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            // Don't show error for hubs - they're optional enhancement
            print("PlexLibraryView: Failed to fetch library hubs: \(error)")
        }
    }

    private func refresh() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        isLoading = true
        async let itemsFetch: () = fetchFromServer(serverURL: serverURL, token: token)
        async let hubsFetch: () = fetchLibraryHubs(serverURL: serverURL, token: token)
        _ = await (itemsFetch, hubsFetch)
    }
}

#Preview {
    NavigationStack {
        PlexLibraryView(libraryKey: "1", libraryTitle: "Movies")
    }
}
