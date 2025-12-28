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

    @Environment(\.openSidebar) private var openSidebar
    @Environment(\.nestedNavigationState) private var nestedNavState
    @Environment(\.focusScopeManager) private var focusScopeManager
    @Environment(\.isSidebarVisible) private var isSidebarVisible

    @StateObject private var authManager = PlexAuthManager.shared
    private let dataStore = PlexDataStore.shared
    @AppStorage("showLibraryHero") private var showLibraryHero = true
    @AppStorage("showLibraryRecommendations") private var showLibraryRecommendations = true
    @State private var items: [PlexMetadata] = []
    @State private var hubs: [PlexHub] = []  // Library-specific hubs from Plex API
    @State private var isLoading = false
    @State private var isLoadingMore = false  // Loading additional pages
    @State private var error: String?
    @State private var selectedItem: PlexMetadata?
    @State private var heroItem: PlexMetadata?
    @State private var lastLoadedLibraryKey: String?  // Track which library is currently loaded
    @State private var hasPrefetched = false  // Track if we've already prefetched for this library
    @State private var hasMoreItems = true  // Whether there are more items to load
    @State private var totalItemCount: Int = 0  // Total items in this library
    @State private var cachedProcessedHubs: [PlexHub] = []  // Memoized hubs to avoid recalculation
    @State private var loadingTask: Task<Void, Never>?  // Track current loading task for cancellation

    #if os(tvOS)
    @FocusState private var focusedItemId: String?  // Track focused item by "context:itemId" format
    @State private var lastPrefetchIndex: Int = -18  // Track last prefetch position for throttling

    /// Create a unique focus ID for a grid item
    private func gridFocusId(for item: PlexMetadata) -> String {
        "libraryGrid:\(item.ratingKey ?? "")"
    }
    #endif

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

    /// Essential hub types that are always shown (Continue Watching, Recently Added, Recently Released, Recently Played)
    private func isEssentialHub(_ hub: PlexHub) -> Bool {
        let identifier = hub.hubIdentifier?.lowercased() ?? ""
        let title = hub.title?.lowercased() ?? ""

        // Continue Watching / On Deck
        if identifier.contains("continuewatching") || title.contains("continue watching") ||
           identifier.contains("ondeck") || title.contains("on deck") {
            return true
        }

        // Recently Added (video and music)
        if identifier.contains("recentlyadded") || title.contains("recently added") {
            return true
        }

        // Recently Released (by year)
        if identifier.contains("recentlyreleased") || title.contains("recently released") ||
           identifier.contains("newestreleases") || title.contains("newest releases") {
            return true
        }

        // Recently Played (music)
        if identifier.contains("recentlyplayed") || title.contains("recently played") {
            return true
        }

        return false
    }

    /// Essential hubs only (Continue Watching, Recently Added, Recently Released)
    private var essentialHubs: [PlexHub] {
        cachedProcessedHubs.filter { isEssentialHub($0) }
    }

    /// Discovery/recommendation hubs (Rediscover, Because you watched, etc.)
    private var discoveryHubs: [PlexHub] {
        cachedProcessedHubs.filter { !isEssentialHub($0) }
    }

    /// Processes hubs to combine Continue Watching and On Deck, similar to PlexHomeView
    /// Called once when hubs change, result is cached in cachedProcessedHubs
    private func computeProcessedHubs(from hubsToProcess: [PlexHub]) -> [PlexHub] {
        var result: [PlexHub] = []
        var continueWatchingItems: [PlexMetadata] = []
        var seenRatingKeys: Set<String> = []

        for hub in hubsToProcess {
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
                // Include all non-continue-watching hubs
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
        NavigationStack {
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
                // Cancel any previous loading task - .task(id:) already cancels when id changes
                loadingTask?.cancel()

                error = nil

                // Check if this is a different library than what's currently loaded
                let isNewLibrary = lastLoadedLibraryKey != libraryKey

                if authManager.isAuthenticated {
                    if isNewLibrary {
                        // IMMEDIATELY update hero and clear hubs to prevent stale content flash
                        hubs = []  // Clear hubs first so essentialHubs is empty
                        heroItem = dataStore.getCachedHero(forLibrary: libraryKey)  // Load cached hero immediately (sync)

                        // Reset state for new library
                        hasPrefetched = false
                        hasMoreItems = true
                        totalItemCount = 0

                        // Load cached data FIRST before clearing anything
                        let cachedItems = await getCachedItems()

                        if !cachedItems.isEmpty {
                            // Atomic swap: replace items and select new hero in one go
                            items = cachedItems
                            lastLoadedLibraryKey = libraryKey

                            // Only select hero if we don't have a cached one
                            if heroItem == nil {
                                selectHeroItemFromCurrentData()
                            }

                            // Refresh in background silently
                            await loadItemsInBackground()
                        } else {
                            // No cache - need to show loading state
                            items = []
                            lastLoadedLibraryKey = libraryKey
                            await loadItems()

                        }
                    } else {
                        // Same library - just refresh in background
                        await loadItemsInBackground()
                    }
                } else {
                    // Not authenticated - clear everything
                    items = []
                    hubs = []
                    heroItem = nil
                    lastLoadedLibraryKey = nil
                }
            }
            .refreshable {
                await refresh()
            }
            .navigationDestination(item: $selectedItem) { item in
                PlexDetailView(item: item)
            }
        }
        // Tell parent we're in nested navigation when viewing detail
        .onChange(of: selectedItem) { _, newValue in
            let isNested = newValue != nil
            nestedNavState.isNested = isNested
            if isNested {
                // Set the go back action to clear selectedItem
                nestedNavState.goBackAction = { [weak nestedNavState] in
                    selectedItem = nil
                    nestedNavState?.isNested = false
                }
            } else {
                nestedNavState.goBackAction = nil
            }
        }
        #if os(tvOS)
        // Save focus when it changes (only when content scope is active)
        .onChange(of: focusedItemId) { _, newValue in
            guard focusScopeManager.isScopeActive(.content) else { return }
            if let newValue {
                // Library grid items use "libraryGrid:itemId" format
                let parts = newValue.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    focusScopeManager.setFocus(
                        itemId: String(parts[1]),
                        context: String(parts[0]),
                        scope: .content
                    )
                } else {
                    focusScopeManager.setFocus(itemId: newValue, scope: .content)
                }
            }
        }
        // Restore focus when scope becomes active
        .onChange(of: focusScopeManager.restoreTrigger) { _, _ in
            // Only restore focus if not in nested navigation (detail view)
            if selectedItem == nil,
               focusScopeManager.isScopeActive(.content),
               let savedItem = focusScopeManager.focusedItem {
                // Reconstruct the composite ID
                if let context = savedItem.context {
                    focusedItemId = "\(context):\(savedItem.itemId)"
                } else {
                    focusedItemId = savedItem.itemId
                }
            }
        }
        #endif
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                essentialRowsView
                heroSectionView
                discoveryRowsView
                librarySectionHeader
                libraryGridView

                // Loading more indicator
                if isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Spacer()
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .id(libraryKey)  // Force fresh ScrollView when library changes - starts at top
        #if os(tvOS)
        .ignoresSafeArea(edges: .top)
        #endif
        .onAppear {
            // Hero will be selected when items load via task handler
            if heroItem == nil && !items.isEmpty {
                selectHeroItem()
            }
        }
        .onChange(of: items.count) { oldCount, newCount in
            // Consolidated handler: hero selection + prefetch
            if heroItem == nil {
                selectHeroItem()
            }
            handleItemsCountChange(oldCount: oldCount, newCount: newCount)
        }
        .onChange(of: hubs.count) { _, _ in
            // Recompute cached hubs (memoization)
            cachedProcessedHubs = computeProcessedHubs(from: hubs)
            // Only reselect hero if we don't have one yet (avoid redundant selection)
            if heroItem == nil {
                selectHeroItem()
            }
        }
    }

    // MARK: - Hero Selection

    private func selectHeroItem() {
        // Check cache first - heroes persist across navigation
        if let cachedHero = dataStore.getCachedHero(forLibrary: libraryKey) {
            heroItem = cachedHero
            return
        }

        // Try to get hero from recently added hub first
        let recentlyAddedHub = hubs.first { hub in
            let identifier = hub.hubIdentifier?.lowercased() ?? ""
            let title = hub.title?.lowercased() ?? ""
            return identifier.contains("recentlyadded") || title.contains("recently added")
        }

        if let hubItems = recentlyAddedHub?.Metadata, !hubItems.isEmpty {
            if let newHero = hubItems.randomElement() {
                heroItem = newHero
                dataStore.cacheHero(newHero, forLibrary: libraryKey)
            }
            return
        }

        // Fallback to items sorted by addedAt
        if !items.isEmpty {
            let recentItems = items.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }.prefix(10)
            if let newHero = recentItems.randomElement() ?? items.first {
                heroItem = newHero
                dataStore.cacheHero(newHero, forLibrary: libraryKey)
            }
        }
    }

    // MARK: - Hero Section View

    @ViewBuilder
    private var heroSectionView: some View {
        #if os(tvOS)
        // Only show hero when there are essential rows above it (prevents flash at top during library switch)
        if showLibraryHero, let hero = heroItem, !essentialHubs.isEmpty {
            HeroView(
                item: hero,
                serverURL: authManager.selectedServerURL ?? "",
                authToken: authManager.authToken ?? "",
                focusTarget: $focusedItemId,
                targetValue: "hero"
            ) {
                selectedItem = hero
            }
            .id("hero-\(libraryKey)-\(hero.ratingKey ?? "")")
            .padding(.top, 48)
        }
        #endif
    }

    // MARK: - Essential Rows View (Continue Watching, Recently Added, Recently Released)

    @ViewBuilder
    private var essentialRowsView: some View {
        if !essentialHubs.isEmpty {
            VStack(alignment: .leading, spacing: 40) {
                ForEach(essentialHubs, id: \.hubIdentifier) { hub in
                    if let hubItems = hub.Metadata, !hubItems.isEmpty {
                        let isContinueWatching = hub.hubIdentifier?.lowercased().contains("continuewatching") == true ||
                                                 hub.title?.lowercased().contains("continue watching") == true
                        MediaRow(
                            title: hub.title ?? "Untitled",
                            items: hubItems,
                            serverURL: authManager.selectedServerURL ?? "",
                            authToken: authManager.authToken ?? "",
                            contextMenuSource: isContinueWatching ? .continueWatching : .library,
                            onItemSelected: { item in
                                selectedItem = item
                            },
                            onRefreshNeeded: {
                                await refresh()
                            }
                        )
                    }
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 80)
            .padding(.top, 100)  // Extra top padding since essential rows are first
            #else
            .padding(.horizontal, 40)
            .padding(.top, 24)
            #endif
        }
    }

    // MARK: - Discovery Rows View (Rediscover, Recommendations, etc.)

    @ViewBuilder
    private var discoveryRowsView: some View {
        if showLibraryRecommendations && !discoveryHubs.isEmpty {
            VStack(alignment: .leading, spacing: 40) {
                ForEach(discoveryHubs, id: \.hubIdentifier) { hub in
                    if let hubItems = hub.Metadata, !hubItems.isEmpty {
                        MediaRow(
                            title: hub.title ?? "Untitled",
                            items: hubItems,
                            serverURL: authManager.selectedServerURL ?? "",
                            authToken: authManager.authToken ?? "",
                            contextMenuSource: .library,
                            onItemSelected: { item in
                                selectedItem = item
                            },
                            onRefreshNeeded: {
                                await refresh()
                            }
                        )
                    }
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 80)
            .padding(.top, 48)
            #else
            .padding(.horizontal, 40)
            .padding(.top, 24)
            #endif
        }
    }

    // MARK: - Library Section Header

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

    // MARK: - Library Grid View

    private var libraryGridView: some View {
        LazyVGrid(columns: columns, spacing: 40) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                libraryGridItem(item: item, index: index)
            }
        }
        #if os(tvOS)
        .padding(.horizontal, 80)
        .padding(.vertical, 28)
        .padding(.bottom, 60)
        .focusSection()  // Help focus engine navigate the grid efficiently
        #else
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
        #endif
    }

    @ViewBuilder
    private func libraryGridItem(item: PlexMetadata, index: Int) -> some View {
        Button {
            selectedItem = item
        } label: {
            // EquatableView tells SwiftUI to use our custom == to skip unnecessary re-renders
            EquatableView(content: MediaPosterCard(
                item: item,
                serverURL: authManager.selectedServerURL ?? "",
                authToken: authManager.authToken ?? ""
            ))
        }
        #if os(tvOS)
        .buttonStyle(CardButtonStyle())
        .focused($focusedItemId, equals: gridFocusId(for: item))
        .modifier(LeftEdgeSidebarTrigger(isFirstItem: index % 6 == 0, openSidebar: openSidebar))
        .onAppear {
            // Trigger loading more items when nearing the end
            if index >= items.count - 12 && hasMoreItems && !isLoadingMore {
                Task { await loadMoreItems() }
            }
            // Prefetch images ahead of scroll position
            if index > lastPrefetchIndex + 3 {
                lastPrefetchIndex = index
                prefetchImagesAhead(from: index)
            }
        }
        #else
        .buttonStyle(.plain)
        #endif
        .mediaItemContextMenu(
            item: item,
            serverURL: authManager.selectedServerURL ?? "",
            authToken: authManager.authToken ?? "",
            source: .library,
            onRefreshNeeded: {
                await refresh()
            }
        )
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

    /// Full load with loading state (used when no cache exists)
    private func loadItems() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else {
            error = "Not authenticated"
            items = []
            hubs = []
            return
        }

        // No cache - show loading and fetch both
        isLoading = true
        async let itemsFetch: () = fetchFromServer(serverURL: serverURL, token: token, updateLoading: true)
        async let hubsFetch: () = fetchLibraryHubs(serverURL: serverURL, token: token)
        _ = await (itemsFetch, hubsFetch)
        // Select hero after data loads
        selectHeroItem()
    }

    /// Background refresh without loading state (used when cache exists)
    private func loadItemsInBackground() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        // Fetch both items and hubs silently in background
        async let itemsFetch: () = fetchFromServer(serverURL: serverURL, token: token, updateLoading: false)
        async let hubsFetch: () = fetchLibraryHubs(serverURL: serverURL, token: token)
        _ = await (itemsFetch, hubsFetch)

        // Only reselect hero if hubs loaded and we don't have one yet
        // or if hubs have better candidates (recently added)
        if heroItem == nil {
            selectHeroItem()
        }
    }
    
    /// Select hero from currently loaded items/hubs (for instant display)
    private func selectHeroItemFromCurrentData() {
        // Check cache first - heroes persist across navigation
        if let cachedHero = dataStore.getCachedHero(forLibrary: libraryKey) {
            heroItem = cachedHero
            return
        }

        // When switching libraries, hubs might not be loaded yet, so prioritize items
        // Try items first (they're available immediately from cache)
        if !items.isEmpty {
            let recentItems = items.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }.prefix(10)
            if let newHero = recentItems.randomElement() ?? items.first {
                heroItem = newHero
                dataStore.cacheHero(newHero, forLibrary: libraryKey)
            }
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
                if let newHero = hubItems.randomElement() {
                    heroItem = newHero
                    dataStore.cacheHero(newHero, forLibrary: libraryKey)
                }
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

    private let pageSize = 100  // Items per page

    private func fetchFromServer(serverURL: String, token: String, updateLoading: Bool) async {
        do {
            let result = try await networkManager.getLibraryItemsWithTotal(
                serverURL: serverURL,
                authToken: token,
                sectionId: libraryKey,
                start: 0,
                size: pageSize
            )

            // Update total count for pagination
            if let total = result.totalSize {
                totalItemCount = total
                hasMoreItems = result.items.count < total
            } else {
                // If no totalSize, assume there might be more if we got a full page
                hasMoreItems = result.items.count >= pageSize
            }

            // Only update items if they're actually different (prevents unnecessary re-renders)
            if !itemsAreEqual(items, result.items) {
                items = result.items
            }

            // Cache based on type
            if let firstItem = result.items.first {
                if firstItem.type == "movie" {
                    await cacheManager.cacheMovies(result.items, forLibrary: libraryKey)
                } else if firstItem.type == "show" {
                    await cacheManager.cacheShows(result.items, forLibrary: libraryKey)
                }
            }

            error = nil
        } catch {
            // Ignore cancellation errors - they happen when views are recreated
            if (error as NSError).code == NSURLErrorCancelled {
                if updateLoading { isLoading = false }
                return
            }
            if items.isEmpty {
                self.error = error.localizedDescription
            }
        }
        if updateLoading { isLoading = false }
    }

    /// Load more items for infinite scroll
    private func loadMoreItems() async {
        guard hasMoreItems,
              !isLoadingMore,
              let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        isLoadingMore = true

        do {
            let result = try await networkManager.getLibraryItemsWithTotal(
                serverURL: serverURL,
                authToken: token,
                sectionId: libraryKey,
                start: items.count,
                size: pageSize
            )

            // Update total count
            if let total = result.totalSize {
                totalItemCount = total
            }

            if result.items.isEmpty {
                // No more items
                hasMoreItems = false
            } else {
                // Append new items, avoiding duplicates
                let existingKeys = Set(items.compactMap { $0.ratingKey })
                let newItems = result.items.filter { item in
                    guard let key = item.ratingKey else { return false }
                    return !existingKeys.contains(key)
                }

                if !newItems.isEmpty {
                    items.append(contentsOf: newItems)
                    if let firstItem = items.first {
                        if firstItem.type == "movie" {
                            await cacheManager.cacheMovies(items, forLibrary: libraryKey)
                        } else if firstItem.type == "show" {
                            await cacheManager.cacheShows(items, forLibrary: libraryKey)
                        }
                    }
                }

                // Check if we've reached the end
                if let total = result.totalSize {
                    hasMoreItems = items.count < total
                } else {
                    hasMoreItems = result.items.count >= pageSize
                }
            }
        } catch {
            // Ignore errors for pagination - just stop loading more
            if (error as NSError).code != NSURLErrorCancelled {
                print("Failed to load more items: \(error)")
            }
        }

        isLoadingMore = false
    }

    /// Compare two item arrays by ratingKey to avoid unnecessary state updates
    private func itemsAreEqual(_ lhs: [PlexMetadata], _ rhs: [PlexMetadata]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        // Compare by ratingKey which is the unique identifier
        let lhsKeys = lhs.compactMap { $0.ratingKey }
        let rhsKeys = rhs.compactMap { $0.ratingKey }
        return lhsKeys == rhsKeys
    }

    private func fetchLibraryHubs(serverURL: String, token: String) async {
        do {
            let fetchedHubs = try await networkManager.getLibraryHubs(
                serverURL: serverURL,
                authToken: token,
                sectionId: libraryKey
            )

            // Debug: log hub info for troubleshooting
            print("📚 Library \(libraryKey) hubs: \(fetchedHubs.count)")
            for hub in fetchedHubs {
                print("  - \(hub.hubIdentifier ?? "nil"): \(hub.title ?? "nil") (\(hub.Metadata?.count ?? 0) items)")
            }

            // Only update hubs if they're actually different
            if !hubsAreEqual(hubs, fetchedHubs) {
                hubs = fetchedHubs
            }
        } catch {
            // Ignore cancellation errors
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            print("📚 Failed to fetch hubs for library \(libraryKey): \(error)")
            // Don't show error for hubs - they're optional enhancement
        }
    }

    /// Compare two hub arrays to avoid unnecessary state updates
    private func hubsAreEqual(_ lhs: [PlexHub], _ rhs: [PlexHub]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        // Compare by hubIdentifier and item counts
        for (l, r) in zip(lhs, rhs) {
            if l.hubIdentifier != r.hubIdentifier { return false }
            if l.Metadata?.count != r.Metadata?.count { return false }
        }
        return true
    }

    private func refresh() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        isLoading = true
        async let itemsFetch: () = fetchFromServer(serverURL: serverURL, token: token, updateLoading: true)
        async let hubsFetch: () = fetchLibraryHubs(serverURL: serverURL, token: token)
        _ = await (itemsFetch, hubsFetch)
    }

    // MARK: - Focus Management

    #if os(tvOS)
    /// Prefetch poster images for visible and upcoming items
    private func prefetchImages() {
        guard !items.isEmpty,
              let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        hasPrefetched = true

        // Prefetch first 20 items (visible + next row)
        let prefetchCount = min(20, items.count)
        let urlsToPreload: [URL] = items.prefix(prefetchCount).compactMap { item in
            guard let thumb = posterThumb(for: item) else { return nil }
            var urlString = "\(serverURL)\(thumb)"
            if !urlString.contains("X-Plex-Token") {
                urlString += urlString.contains("?") ? "&" : "?"
                urlString += "X-Plex-Token=\(token)"
            }
            return URL(string: urlString)
        }

        // Fire off prefetch in background
        Task.detached(priority: .background) {
            await ImageCacheManager.shared.prefetch(urls: urlsToPreload)
        }
    }

    /// Prefetch images ahead of the current scroll position
    /// Called frequently to ensure images are loaded before user reaches them
    private func prefetchImagesAhead(from index: Int) {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        // Prefetch the next 30 items (~5 rows of 6) ahead of current position
        let prefetchStart = index + 3  // Start just ahead of current position
        let prefetchEnd = min(prefetchStart + 30, items.count)

        guard prefetchStart < items.count else { return }

        let itemsToPrefetch = Array(items[prefetchStart..<prefetchEnd])
        guard !itemsToPrefetch.isEmpty else { return }

        let urlsToPreload: [URL] = itemsToPrefetch.compactMap { item in
            guard let thumb = posterThumb(for: item) else { return nil }
            var urlString = "\(serverURL)\(thumb)"
            if !urlString.contains("X-Plex-Token") {
                urlString += urlString.contains("?") ? "&" : "?"
                urlString += "X-Plex-Token=\(token)"
            }
            return URL(string: urlString)
        }

        guard !urlsToPreload.isEmpty else { return }

        // Fire off prefetch with utility priority for timely loading
        Task.detached(priority: .utility) {
            await ImageCacheManager.shared.prefetch(urls: urlsToPreload)
        }
    }
    #endif

    /// Handle items count change - triggers prefetch on tvOS
    private func handleItemsCountChange(oldCount: Int, newCount: Int) {
        #if os(tvOS)
        if oldCount == 0 && newCount > 0 {
            prefetchImages()
        } else if !hasPrefetched && newCount > 0 {
            prefetchImages()
        }
        #endif
    }

    private func posterThumb(for item: PlexMetadata) -> String? {
        if item.type == "episode" {
            return item.grandparentThumb ?? item.parentThumb ?? item.thumb
        }
        return item.thumb
    }
}

#Preview {
    NavigationStack {
        PlexLibraryView(libraryKey: "1", libraryTitle: "Movies")
    }
}
