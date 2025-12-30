//
//  PlexDataStore.swift
//  Rivulet
//
//  Shared data store for Plex content that persists across view recreations
//

import Foundation
import Combine

@MainActor
class PlexDataStore: ObservableObject {
    static let shared = PlexDataStore()

    // MARK: - Published State

    @Published var hubs: [PlexHub] = []
    @Published var libraries: [PlexLibrary] = []
    @Published var isLoadingHubs = false
    @Published var isLoadingLibraries = false
    @Published var hubsError: String?
    @Published var librariesError: String?

    /// Increments whenever hubs content changes (not just count)
    /// Views should watch this to trigger UI updates when items change
    @Published private(set) var hubsVersion: UUID = UUID()

    // MARK: - Hero Cache (per library)

    /// Cached hero items per library key - persists across navigation
    private var heroCache: [String: PlexMetadata] = [:]

    /// Get cached hero for a library (returns nil if not cached)
    func getCachedHero(forLibrary libraryKey: String) -> PlexMetadata? {
        return heroCache[libraryKey]
    }

    /// Cache a hero for a library
    func cacheHero(_ hero: PlexMetadata, forLibrary libraryKey: String) {
        heroCache[libraryKey] = hero
    }

    /// Clear hero cache (e.g., on sign out)
    func clearHeroCache() {
        heroCache.removeAll()
    }

    // MARK: - Dependencies

    private let networkManager = PlexNetworkManager.shared
    private let cacheManager = CacheManager.shared
    private let authManager = PlexAuthManager.shared
    let librarySettings = LibrarySettingsManager.shared

    // MARK: - Computed Properties

    /// Libraries filtered by visibility settings and sorted by user preference
    /// Use this for displaying in the sidebar
    var visibleLibraries: [PlexLibrary] {
        librarySettings.filterAndSortLibraries(libraries)
    }

    /// Video libraries only (movies, shows), filtered and sorted
    var visibleVideoLibraries: [PlexLibrary] {
        visibleLibraries.filter { $0.isVideoLibrary }
    }

    /// Music libraries only (artist), filtered and sorted
    var visibleMusicLibraries: [PlexLibrary] {
        visibleLibraries.filter { $0.isMusicLibrary }
    }

    /// Video and music libraries combined (for sidebar display)
    var visibleMediaLibraries: [PlexLibrary] {
        visibleLibraries.filter { $0.isVideoLibrary || $0.isMusicLibrary }
    }

    /// Check if any music library is visible in the sidebar
    var hasMusicLibraryVisible: Bool {
        !visibleMusicLibraries.isEmpty
    }

    // Track if initial load has been attempted
    private var hubsLoadTask: Task<Void, Never>?
    private var librariesLoadTask: Task<Void, Never>?

    private init() {
        print("📦 PlexDataStore: Initialized")
    }

    // MARK: - Hubs (Home View)

    func loadHubsIfNeeded() async {
        // If we already have data, skip
        if !hubs.isEmpty {
            print("📦 PlexDataStore: Hubs already loaded (\(hubs.count) items), skipping")
            return
        }

        // If already loading, wait for that task
        if let existingTask = hubsLoadTask {
            print("📦 PlexDataStore: Hubs load already in progress, waiting...")
            await existingTask.value
            return
        }

        print("📦 PlexDataStore: Starting hubs load...")

        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else {
            print("📦 PlexDataStore: Not authenticated - serverURL: \(authManager.selectedServerURL ?? "nil"), token: \(authManager.authToken != nil ? "present" : "nil")")
            hubsError = "Not authenticated"
            return
        }

        print("📦 PlexDataStore: Auth OK - serverURL: \(serverURL)")

        isLoadingHubs = true
        hubsError = nil

        // Create a non-cancellable task for the network request
        hubsLoadTask = Task {
            // Try cache first
            print("📦 PlexDataStore: Checking cache for hubs...")
            if let cached = await cacheManager.getCachedHubs(), !cached.isEmpty {
                print("📦 PlexDataStore: Found \(cached.count) cached hubs")
                await MainActor.run {
                    self.hubs = cached
                    self.hubsVersion = UUID()
                    self.isLoadingHubs = false
                }
                // Background refresh
                await fetchHubsFromServer(serverURL: serverURL, token: token, updateLoading: false)
            } else {
                print("📦 PlexDataStore: No cache, fetching from server...")
                await fetchHubsFromServer(serverURL: serverURL, token: token, updateLoading: true)
            }
        }

        await hubsLoadTask?.value
        hubsLoadTask = nil
    }

    private func fetchHubsFromServer(serverURL: String, token: String, updateLoading: Bool) async {
        print("📦 PlexDataStore: Fetching hubs from \(serverURL)/hubs")

        do {
            let fetchedHubs = try await fetchHubsOffMain(serverURL: serverURL, token: token)
            print("📦 PlexDataStore: ✅ Fetched \(fetchedHubs.count) hubs")

            // Only update if hubs actually changed (prevents unnecessary re-renders)
            if !hubsAreEqual(self.hubs, fetchedHubs) {
                self.hubs = fetchedHubs
                self.hubsVersion = UUID()  // Signal that content changed
                print("📦 PlexDataStore: Hubs updated (changed)")
            } else {
                print("📦 PlexDataStore: Hubs unchanged, skipping update")
            }
            self.hubsError = nil
            if updateLoading {
                self.isLoadingHubs = false
            }
            await cacheManager.cacheHubs(fetchedHubs)
        } catch {
            let nsError = error as NSError
            print("📦 PlexDataStore: ❌ Hubs fetch error: \(error)")
            print("📦 PlexDataStore: Error domain: \(nsError.domain), code: \(nsError.code)")

            // Ignore cancellation errors
            if nsError.code == NSURLErrorCancelled {
                print("📦 PlexDataStore: Request was cancelled")
                return
            }

            if self.hubs.isEmpty {
                self.hubsError = error.localizedDescription
            }
            if updateLoading {
                self.isLoadingHubs = false
            }
        }
    }

    func refreshHubs() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        print("📦 PlexDataStore: Refreshing hubs...")
        isLoadingHubs = true
        await cacheManager.clearOnDeckCache()
        await fetchHubsFromServer(serverURL: serverURL, token: token, updateLoading: true)
    }

    // MARK: - Libraries

    func loadLibrariesIfNeeded() async {
        // If we already have data, skip
        if !libraries.isEmpty {
            print("📦 PlexDataStore: Libraries already loaded (\(libraries.count) items), skipping")
            return
        }

        // If already loading, wait for that task
        if let existingTask = librariesLoadTask {
            print("📦 PlexDataStore: Libraries load already in progress, waiting...")
            await existingTask.value
            return
        }

        print("📦 PlexDataStore: Starting libraries load...")

        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else {
            print("📦 PlexDataStore: Not authenticated for libraries")
            librariesError = "Not authenticated"
            return
        }

        print("📦 PlexDataStore: Auth OK for libraries - serverURL: \(serverURL)")

        isLoadingLibraries = true
        librariesError = nil

        // Create a non-cancellable task for the network request
        librariesLoadTask = Task {
            // Try cache first
            print("📦 PlexDataStore: Checking cache for libraries...")
            if let cached = await cacheManager.getCachedLibraries(), !cached.isEmpty {
                print("📦 PlexDataStore: Found \(cached.count) cached libraries")
                await MainActor.run {
                    self.libraries = cached
                    self.isLoadingLibraries = false
                }
                // Background refresh
                await fetchLibrariesFromServer(serverURL: serverURL, token: token, updateLoading: false)
            } else {
                print("📦 PlexDataStore: No cache, fetching libraries from server...")
                await fetchLibrariesFromServer(serverURL: serverURL, token: token, updateLoading: true)
            }
        }

        await librariesLoadTask?.value
        librariesLoadTask = nil
    }

    private func fetchLibrariesFromServer(serverURL: String, token: String, updateLoading: Bool) async {
        print("📦 PlexDataStore: Fetching libraries from \(serverURL)/library/sections")

        do {
            let fetched = try await fetchLibrariesOffMain(serverURL: serverURL, token: token)
            print("📦 PlexDataStore: ✅ Fetched \(fetched.count) libraries")

            // Only update if libraries actually changed (prevents unnecessary re-renders)
            if !librariesAreEqual(self.libraries, fetched) {
                self.libraries = fetched
                print("📦 PlexDataStore: Libraries updated (changed)")
            } else {
                print("📦 PlexDataStore: Libraries unchanged, skipping update")
            }
            self.librariesError = nil
            if updateLoading {
                self.isLoadingLibraries = false
            }
            // Sync library order settings with current libraries
            self.librarySettings.syncOrderWithLibraries(fetched)
            await cacheManager.cacheLibraries(fetched)
        } catch {
            let nsError = error as NSError
            print("📦 PlexDataStore: ❌ Libraries fetch error: \(error)")
            print("📦 PlexDataStore: Error domain: \(nsError.domain), code: \(nsError.code)")

            // Ignore cancellation errors
            if nsError.code == NSURLErrorCancelled {
                print("📦 PlexDataStore: Request was cancelled")
                return
            }

            if self.libraries.isEmpty {
                self.librariesError = error.localizedDescription
            }
            if updateLoading {
                self.isLoadingLibraries = false
            }
        }
    }

    // MARK: - Off-main fetch helpers

    private func fetchHubsOffMain(serverURL: String, token: String) async throws -> [PlexHub] {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try await PlexNetworkManager.shared.getHubs(serverURL: serverURL, authToken: token)
        }.value
    }

    private func fetchLibrariesOffMain(serverURL: String, token: String) async throws -> [PlexLibrary] {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try await PlexNetworkManager.shared.getLibraries(serverURL: serverURL, authToken: token)
        }.value
    }

    func refreshLibraries() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        print("📦 PlexDataStore: Refreshing libraries...")
        isLoadingLibraries = true
        await fetchLibrariesFromServer(serverURL: serverURL, token: token, updateLoading: true)
    }

    // MARK: - Optimistic Updates

    /// Update an item's watch status locally (optimistic update)
    /// This immediately reflects the change in UI before the server refresh completes
    func updateItemWatchStatus(ratingKey: String, watched: Bool) {
        var didUpdate = false
        // Update in hubs
        for hubIndex in hubs.indices {
            if var metadata = hubs[hubIndex].Metadata {
                for itemIndex in metadata.indices {
                    if metadata[itemIndex].ratingKey == ratingKey {
                        if watched {
                            metadata[itemIndex].viewCount = (metadata[itemIndex].viewCount ?? 0) + 1
                            metadata[itemIndex].viewOffset = nil
                        } else {
                            metadata[itemIndex].viewCount = 0
                            metadata[itemIndex].viewOffset = nil
                        }
                        hubs[hubIndex].Metadata = metadata
                        didUpdate = true
                        print("📦 PlexDataStore: Optimistically updated \(ratingKey) watched=\(watched) in hub \(hubs[hubIndex].title ?? "unknown")")
                    }
                }
            }
        }
        // Bump version so views recompute their derived state
        if didUpdate {
            hubsVersion = UUID()
        }
    }

    // MARK: - Background Prefetch

    private var prefetchTask: Task<Void, Never>?

    /// Prefetch library content in the background for faster navigation
    /// Call this on app start after authentication is verified
    func startBackgroundPrefetch() {
        // Cancel any existing prefetch
        prefetchTask?.cancel()

        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else {
            print("📦 PlexDataStore: Cannot prefetch - not authenticated")
            return
        }

        prefetchTask = Task(priority: .utility) {
            print("📦 PlexDataStore: Starting background prefetch...")

            // Wait for libraries to be loaded first
            while libraries.isEmpty && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            guard !Task.isCancelled else { return }

            // Prefetch content for each visible/pinned video library only
            for library in visibleVideoLibraries {
                guard !Task.isCancelled else { break }

                let libraryKey = library.key

                // Check if already cached
                let hasMoviesCache = await cacheManager.getCachedMovies(forLibrary: libraryKey) != nil
                let hasShowsCache = await cacheManager.getCachedShows(forLibrary: libraryKey) != nil
                let hasHubsCache = await cacheManager.getCachedLibraryHubs(forLibrary: libraryKey) != nil

                if hasMoviesCache || hasShowsCache {
                    print("📦 PlexDataStore: Library \(library.title) already cached, skipping items")
                } else {
                    // Fetch and cache library items
                    do {
                        print("📦 PlexDataStore: Prefetching items for \(library.title)...")
                        let result = try await networkManager.getLibraryItemsWithTotal(
                            serverURL: serverURL,
                            authToken: token,
                            sectionId: libraryKey,
                            start: 0,
                            size: 100
                        )

                        // Cache based on type
                        if let firstItem = result.items.first {
                            if firstItem.type == "movie" {
                                await cacheManager.cacheMovies(result.items, forLibrary: libraryKey)
                            } else if firstItem.type == "show" {
                                await cacheManager.cacheShows(result.items, forLibrary: libraryKey)
                            }
                        }
                        print("📦 PlexDataStore: ✅ Prefetched \(result.items.count) items for \(library.title)")

                        // Prefetch poster images for first 30 items
                        prefetchImages(for: result.items, serverURL: serverURL, token: token)
                    } catch {
                        print("📦 PlexDataStore: ⚠️ Failed to prefetch items for \(library.title): \(error.localizedDescription)")
                    }
                }

                // Prefetch library hubs
                if hasHubsCache {
                    print("📦 PlexDataStore: Library \(library.title) hubs already cached, skipping")
                } else {
                    do {
                        print("📦 PlexDataStore: Prefetching hubs for \(library.title)...")
                        let hubs = try await networkManager.getLibraryHubs(
                            serverURL: serverURL,
                            authToken: token,
                            sectionId: libraryKey
                        )
                        await cacheManager.cacheLibraryHubs(hubs, forLibrary: libraryKey)
                        print("📦 PlexDataStore: ✅ Prefetched \(hubs.count) hubs for \(library.title)")
                    } catch {
                        print("📦 PlexDataStore: ⚠️ Failed to prefetch hubs for \(library.title): \(error.localizedDescription)")
                    }
                }

                // Small delay between libraries to avoid overwhelming the server
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }

            // Prefetch home hub images and next episodes for Continue Watching
            await prefetchHubContent(serverURL: serverURL, token: token)

            print("📦 PlexDataStore: Background prefetch complete")
        }
    }

    // MARK: - Image Prefetching

    /// Build image URL for a metadata item
    private func buildImageURL(for item: PlexMetadata, serverURL: String, token: String) -> URL? {
        // For episodes, prefer the series poster
        let thumb: String?
        if item.type == "episode" {
            thumb = item.grandparentThumb ?? item.parentThumb ?? item.thumb
        } else {
            thumb = item.thumb
        }

        guard let thumbPath = thumb else { return nil }
        var urlString = "\(serverURL)\(thumbPath)"
        if !urlString.contains("X-Plex-Token") {
            urlString += urlString.contains("?") ? "&" : "?"
            urlString += "X-Plex-Token=\(token)"
        }
        return URL(string: urlString)
    }

    /// Prefetch poster images for a list of items
    private func prefetchImages(for items: [PlexMetadata], serverURL: String, token: String) {
        let imageURLs = items.compactMap { buildImageURL(for: $0, serverURL: serverURL, token: token) }
        guard !imageURLs.isEmpty else { return }

        print("📦 PlexDataStore: Prefetching \(imageURLs.count) poster images...")
        Task.detached(priority: .utility) {
            await ImageCacheManager.shared.prefetch(urls: imageURLs)
        }
    }

    /// Prefetch hub content including images and next episodes for Continue Watching
    private func prefetchHubContent(serverURL: String, token: String) async {
        guard !hubs.isEmpty else { return }

        print("📦 PlexDataStore: Prefetching hub content...")

        // Collect all hub items for image prefetching
        var allHubItems: [PlexMetadata] = []
        var continueWatchingEpisodes: [PlexMetadata] = []

        for hub in hubs {
            guard let items = hub.Metadata else { continue }
            allHubItems.append(contentsOf: items)

            // Identify Continue Watching / On Deck hubs
            let identifier = hub.hubIdentifier?.lowercased() ?? ""
            let isContinueWatching = identifier.contains("continuewatching") ||
                                     identifier.contains("ondeck") ||
                                     identifier.contains("inprogress")

            if isContinueWatching {
                // Collect TV episodes for next episode prefetching
                let episodes = items.filter { $0.type == "episode" }
                continueWatchingEpisodes.append(contentsOf: episodes)
            }
        }

        // Prefetch poster images for all hub items
        prefetchImages(for: allHubItems, serverURL: serverURL, token: token)

        // Prefetch next episodes for Continue Watching TV episodes
        if !continueWatchingEpisodes.isEmpty {
            await prefetchNextEpisodes(for: continueWatchingEpisodes, serverURL: serverURL, token: token)
        }
    }

    // MARK: - Next Episode Prefetching

    /// Cache for prefetched next episodes (keyed by current episode ratingKey)
    private(set) var nextEpisodeCache: [String: PlexMetadata] = [:]

    /// Prefetch next episodes for Continue Watching items
    private func prefetchNextEpisodes(for episodes: [PlexMetadata], serverURL: String, token: String) async {
        // Limit to first 5 episodes to avoid too many requests
        let episodesToProcess = Array(episodes.prefix(5))
        print("📦 PlexDataStore: Prefetching next episodes for \(episodesToProcess.count) items...")

        for episode in episodesToProcess {
            guard !Task.isCancelled else { break }

            guard let ratingKey = episode.ratingKey else { continue }

            // Skip if already cached
            if nextEpisodeCache[ratingKey] != nil { continue }

            do {
                // Fetch full metadata if parent keys are missing
                var workingEpisode = episode
                if workingEpisode.parentRatingKey == nil || workingEpisode.index == nil {
                    let fullMetadata = try await networkManager.getMetadata(
                        serverURL: serverURL,
                        authToken: token,
                        ratingKey: ratingKey
                    )
                    workingEpisode.parentRatingKey = fullMetadata.parentRatingKey
                    workingEpisode.grandparentRatingKey = fullMetadata.grandparentRatingKey
                    workingEpisode.parentIndex = fullMetadata.parentIndex
                    workingEpisode.index = fullMetadata.index
                }

                guard let seasonKey = workingEpisode.parentRatingKey,
                      let currentIndex = workingEpisode.index else { continue }

                // Get episodes in current season
                let seasonEpisodes = try await networkManager.getChildren(
                    serverURL: serverURL,
                    authToken: token,
                    ratingKey: seasonKey
                )

                // Find next episode
                if let nextEp = seasonEpisodes.first(where: { $0.index == currentIndex + 1 }) {
                    nextEpisodeCache[ratingKey] = nextEp
                    print("📦 PlexDataStore: ✅ Cached next episode for \(episode.title ?? "?"): \(nextEp.episodeString ?? "?")")

                    // Prefetch the next episode's thumbnail
                    if let imageURL = buildImageURL(for: nextEp, serverURL: serverURL, token: token) {
                        Task.detached(priority: .utility) {
                            _ = await ImageCacheManager.shared.image(for: imageURL)
                        }
                    }
                }
                // Note: We don't try next season here to keep prefetch fast
            } catch {
                print("📦 PlexDataStore: ⚠️ Failed to prefetch next episode for \(episode.title ?? "?"): \(error.localizedDescription)")
            }

            // Small delay between requests
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }

    /// Get cached next episode for a given episode ratingKey
    func getCachedNextEpisode(for ratingKey: String) -> PlexMetadata? {
        return nextEpisodeCache[ratingKey]
    }

    /// Clear next episode cache
    func clearNextEpisodeCache() {
        nextEpisodeCache.removeAll()
    }

    // MARK: - Reset (on sign out)

    func reset() {
        print("📦 PlexDataStore: Resetting all data")
        hubsLoadTask?.cancel()
        librariesLoadTask?.cancel()
        prefetchTask?.cancel()
        hubsLoadTask = nil
        librariesLoadTask = nil
        prefetchTask = nil
        hubs = []
        libraries = []
        hubsError = nil
        librariesError = nil
        isLoadingHubs = false
        isLoadingLibraries = false
        nextEpisodeCache.removeAll()
        heroCache.removeAll()
    }

    // MARK: - Diffing Helpers

    /// Compare two hub arrays to avoid unnecessary state updates
    private func hubsAreEqual(_ lhs: [PlexHub], _ rhs: [PlexHub]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) {
            if l.hubIdentifier != r.hubIdentifier { return false }
            if l.Metadata?.count != r.Metadata?.count { return false }
            // Also compare item watch status to detect changes
            if let lItems = l.Metadata, let rItems = r.Metadata {
                for (lItem, rItem) in zip(lItems, rItems) {
                    if lItem.ratingKey != rItem.ratingKey { return false }
                    if lItem.viewCount != rItem.viewCount { return false }
                    if lItem.viewOffset != rItem.viewOffset { return false }
                }
            }
        }
        return true
    }

    /// Compare two library arrays to avoid unnecessary state updates
    private func librariesAreEqual(_ lhs: [PlexLibrary], _ rhs: [PlexLibrary]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let lhsKeys = lhs.map { $0.key }
        let rhsKeys = rhs.map { $0.key }
        return lhsKeys == rhsKeys
    }
}
