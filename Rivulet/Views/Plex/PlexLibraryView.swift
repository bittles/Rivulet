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

    @StateObject private var authManager = PlexAuthManager.shared
    @State private var items: [PlexMetadata] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedItem: PlexMetadata?
    @State private var searchText = ""

    // Focus management
    @Namespace private var namespace

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

    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                notConnectedView
            } else if isLoading && items.isEmpty {
                loadingView
            } else if let error = error, items.isEmpty {
                errorView(error)
            } else if filteredItems.isEmpty && !searchText.isEmpty {
                noResultsView
            } else if items.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .searchable(text: $searchText, prompt: "Search \(libraryTitle)")
        .task(id: libraryKey) {
            // Reset search and error when library changes
            error = nil
            searchText = ""

            if authManager.isAuthenticated {
                await loadItems()
            }
        }
        .refreshable {
            await refresh()
        }
        .sheet(item: $selectedItem) { item in
            PlexDetailView(item: item)
        }
    }

    // MARK: - Filtered Items

    private var filteredItems: [PlexMetadata] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { item in
            (item.title ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header (not focusable)
                libraryHeader
                    .focusable(false)

                // Grid
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.ratingKey) { index, item in
                        Button {
                            selectedItem = item
                        } label: {
                            MediaPosterCard(
                                item: item,
                                serverURL: authManager.selectedServerURL ?? "",
                                authToken: authManager.authToken ?? ""
                            )
                        }
                        .buttonStyle(.plain)
                        #if os(tvOS)
                        .modifier(LibraryFocusModifier(
                            shouldFocus: index == 0,
                            namespace: namespace
                        ))
                        #endif
                    }
                }
                #if os(tvOS)
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
                #else
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                #endif
            }
        }
        #if os(tvOS)
        .focusScope(namespace)
        #endif
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(libraryTitle)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)

            Text("\(filteredItems.count) items")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        #if os(tvOS)
        .padding(.horizontal, 80)
        .padding(.top, 40)
        .padding(.bottom, 32)
        #else
        .padding(.horizontal, 40)
        .padding(.top, 20)
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

    // MARK: - No Results View

    private var noResultsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("No Results")
                .font(.title2)
                .fontWeight(.medium)

            Text("No items match \"\(searchText)\"")
                .font(.body)
                .foregroundStyle(.secondary)
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
            return
        }

        // Try cache first - this is instant from memory/disk
        let cachedItems = await getCachedItems()
        if !cachedItems.isEmpty {
            // Show cached data immediately (no loading state)
            items = cachedItems

            // Refresh in background silently
            await fetchFromServer(serverURL: serverURL, token: token)
            return
        }

        // No cache - show loading and fetch
        items = []
        isLoading = true
        await fetchFromServer(serverURL: serverURL, token: token)
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

    private func refresh() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        isLoading = true
        await fetchFromServer(serverURL: serverURL, token: token)
    }
}

// MARK: - Library Focus Modifier

#if os(tvOS)
struct LibraryFocusModifier: ViewModifier {
    let shouldFocus: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if shouldFocus {
            content.prefersDefaultFocus(in: namespace)
        } else {
            content
        }
    }
}
#endif

#Preview {
    NavigationStack {
        PlexLibraryView(libraryKey: "1", libraryTitle: "Movies")
    }
}
