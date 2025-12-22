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

    // MARK: - Dependencies

    private let networkManager = PlexNetworkManager.shared
    private let cacheManager = CacheManager.shared
    private let authManager = PlexAuthManager.shared

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

            // Log hub details
            for hub in fetchedHubs {
                let itemCount = hub.Metadata?.count ?? 0
                print("📦   Hub: '\(hub.title ?? "?")' - \(itemCount) items")
            }

            await MainActor.run {
                self.hubs = fetchedHubs
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

            // Log library details
            for lib in fetched {
                print("📦   Library: '\(lib.title)' (type: \(lib.type), key: \(lib.key))")
            }

            await MainActor.run {
                self.libraries = fetched
                self.librariesError = nil
                if updateLoading {
                    self.isLoadingLibraries = false
                }
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
}
