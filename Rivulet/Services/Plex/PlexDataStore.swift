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
            let fetchedHubs = try await networkManager.getHubs(serverURL: serverURL, authToken: token)
            print("📦 PlexDataStore: ✅ Fetched \(fetchedHubs.count) hubs")

            await MainActor.run {
                // Only update if hubs actually changed (prevents unnecessary re-renders)
                if !hubsAreEqual(self.hubs, fetchedHubs) {
                    self.hubs = fetchedHubs
                    print("📦 PlexDataStore: Hubs updated (changed)")
                } else {
                    print("📦 PlexDataStore: Hubs unchanged, skipping update")
                }
                self.hubsError = nil
                if updateLoading {
                    self.isLoadingHubs = false
                }
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

            await MainActor.run {
                if self.hubs.isEmpty {
                    self.hubsError = error.localizedDescription
                }
                if updateLoading {
                    self.isLoadingHubs = false
                }
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
            let fetched = try await networkManager.getLibraries(serverURL: serverURL, authToken: token)
            print("📦 PlexDataStore: ✅ Fetched \(fetched.count) libraries")

            await MainActor.run {
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
            }
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

            await MainActor.run {
                if self.libraries.isEmpty {
                    self.librariesError = error.localizedDescription
                }
                if updateLoading {
                    self.isLoadingLibraries = false
                }
            }
        }
    }

    func refreshLibraries() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        print("📦 PlexDataStore: Refreshing libraries...")
        isLoadingLibraries = true
        await fetchLibrariesFromServer(serverURL: serverURL, token: token, updateLoading: true)
    }

    // MARK: - Reset (on sign out)

    func reset() {
        print("📦 PlexDataStore: Resetting all data")
        hubsLoadTask?.cancel()
        librariesLoadTask?.cancel()
        hubsLoadTask = nil
        librariesLoadTask = nil
        hubs = []
        libraries = []
        hubsError = nil
        librariesError = nil
        isLoadingHubs = false
        isLoadingLibraries = false
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
