//
//  PlexSearchView.swift
//  Rivulet
//
//  Search view for Plex libraries with tvOS-style results
//

import SwiftUI

struct PlexSearchView: View {
    @StateObject private var authManager = PlexAuthManager.shared
    @StateObject private var dataStore = PlexDataStore.shared
    @Environment(\.nestedNavigationState) private var nestedNavState
    @Environment(\.contentFocusVersion) private var contentFocusVersion

    @State private var query = ""
    @State private var results: [PlexMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedItem: PlexMetadata?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchToken = 0
    @State private var lastSubmittedQuery = ""

    @FocusState private var isSearchFieldFocused: Bool

    private let networkManager = PlexNetworkManager.shared
    private let minQueryLength = 2
    private let debounceIntervalNs: UInt64 = 350_000_000

    var body: some View {
        NavigationStack {
            if !authManager.isAuthenticated {
                notConnectedView
            } else {
                VStack(spacing: 0) {
                    headerView

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            contentBody
                        }
                        .padding(.bottom, 80)
                    }
                    .scrollClipDisabled()
                }
                .navigationDestination(item: $selectedItem) { item in
                    PlexDetailView(item: item)
                }
            }
        }
        #if os(tvOS)
        .modifier(SearchableModifier(isActive: authManager.isAuthenticated && selectedItem == nil, query: $query))
        #endif
        .task {
            if authManager.isAuthenticated {
                await dataStore.loadLibrariesIfNeeded()
            }
        }
        .onChange(of: query) { _, newValue in
            scheduleSearch(for: newValue)
        }
        .onChange(of: selectedItem) { _, newValue in
            let isNested = newValue != nil
            nestedNavState.isNested = isNested
            if isNested {
                nestedNavState.goBackAction = { [weak nestedNavState] in
                    selectedItem = nil
                    nestedNavState?.isNested = false
                }
            } else {
                nestedNavState.goBackAction = nil
            }
        }
        .onSubmit {
            submitSearch()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if !os(tvOS)
            searchField
            #endif

            if let summary = resultSummary {
                Text(summary)
                    #if os(tvOS)
                    .font(.system(size: 17, weight: .medium))
                    #else
                    .font(.system(size: 15, weight: .medium))
                    #endif
                    .foregroundStyle(.secondary)
            }
        }
        #if os(tvOS)
        .padding(.horizontal, 80)
        .padding(.top, 16)
        #else
        .padding(.horizontal, 32)
        .padding(.top, 32)
        #endif
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                #if os(tvOS)
                .font(.system(size: 20, weight: .semibold))
                #else
                .font(.system(size: 16, weight: .semibold))
                #endif
                .foregroundStyle(.white.opacity(0.7))

            TextField("Search movies, shows, and episodes", text: $query)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    submitSearch()
                }

            if !query.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        #if os(tvOS)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        #else
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        #endif
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(isSearchFieldFocused ? 0.35 : 0.18), lineWidth: 1)
        )
        #if os(tvOS)
        .defaultFocus($isSearchFieldFocused, true)
        #endif
    }

    // MARK: - Content Body

    @ViewBuilder
    private var contentBody: some View {
        if !authManager.isAuthenticated {
            EmptyView()
        } else if trimmedQuery.isEmpty || trimmedQuery.count < minQueryLength {
            searchPromptView
        } else if isAwaitingResults {
            loadingView
        } else if let errorMessage {
            errorView(errorMessage)
        } else if filteredResults.isEmpty {
            noResultsView
        } else {
            resultsView
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsView: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 40) {
            ForEach(groupedResults, id: \.title) { group in
                MediaRow(
                    title: group.title,
                    items: group.items,
                    serverURL: serverURL,
                    authToken: authToken,
                    onItemSelected: { item in
                        selectedItem = item
                    }
                )
            }
        }
        .padding(.bottom, 80)
        #else
        VStack(alignment: .leading, spacing: 28) {
            ForEach(groupedResults, id: \.title) { group in
                Text(group.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 32)

                MediaGrid(
                    items: group.items,
                    serverURL: serverURL,
                    authToken: authToken,
                    onItemSelected: { item in
                        selectedItem = item
                    }
                )
            }
        }
        .padding(.bottom, 60)
        #endif
    }

    private var groupedResults: [(title: String, items: [PlexMetadata])] {
        let titleItems = filteredResults.filter { $0.type == "movie" || $0.type == "show" }
        let episodeItems = filteredResults.filter { $0.type == "episode" || $0.type == "season" }
        var groups: [(title: String, items: [PlexMetadata])] = []

        if !titleItems.isEmpty {
            groups.append((title: "Movies & TV", items: titleItems))
        }

        if !episodeItems.isEmpty {
            groups.append((title: "Episodes & Seasons", items: episodeItems))
        }

        return groups
    }

    private var filteredResults: [PlexMetadata] {
        let visibleKeys = Set(dataStore.visibleVideoLibraries.map { $0.key })
        let types = Set(["movie", "show", "season", "episode"])
        var seen = Set<String>()

        return results.filter { item in
            guard let type = item.type, types.contains(type) else { return false }
            guard let key = item.ratingKey else { return false }
            guard !seen.contains(key) else { return false }
            seen.insert(key)

            if !visibleKeys.isEmpty {
                if let sectionKey = item.librarySectionKey {
                    return visibleKeys.contains(sectionKey)
                }
                if let sectionId = item.librarySectionID {
                    return visibleKeys.contains(String(sectionId))
                }
            }

            return true
        }
    }

    private var resultSummary: String? {
        guard trimmedQuery.count >= minQueryLength else { return nil }
        if isAwaitingResults || errorMessage != nil {
            return nil
        }
        return "\(filteredResults.count) result\(filteredResults.count == 1 ? "" : "s")"
    }

    private var isAwaitingResults: Bool {
        guard trimmedQuery.count >= minQueryLength else { return false }
        return isLoading || lastSubmittedQuery != trimmedQuery
    }

    // MARK: - State Views

    private var searchPromptView: some View {
        let message: String
        if trimmedQuery.isEmpty {
            message = "Search your libraries."
        } else {
            message = "Type at least \(minQueryLength) characters to search."
        }

        return VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Search Plex")
                .font(.title2)
                .fontWeight(.medium)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Searching")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Search Failed")
                .font(.title2)
                .fontWeight(.medium)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            Button {
                submitSearch()
            } label: {
                Text("Try Again")
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("No Results")
                .font(.title2)
                .fontWeight(.medium)

            Text("Try a different title or check your spelling.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

    // MARK: - Search Helpers

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var serverURL: String {
        authManager.selectedServerURL ?? ""
    }

    private var authToken: String {
        authManager.authToken ?? ""
    }

    private func scheduleSearch(for rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= minQueryLength else {
            searchTask?.cancel()
            searchToken += 1
            isLoading = false
            errorMessage = nil
            results = []
            lastSubmittedQuery = ""
            return
        }

        searchTask?.cancel()
        searchToken += 1
        let currentToken = searchToken

        searchTask = Task {
            try? await Task.sleep(nanoseconds: debounceIntervalNs)
            if Task.isCancelled {
                return
            }
            await performSearch(query: trimmed, token: currentToken)
        }
    }

    private func submitSearch() {
        let trimmed = trimmedQuery
        guard trimmed.count >= minQueryLength else { return }
        if trimmed == lastSubmittedQuery && !results.isEmpty {
            return
        }

        searchTask?.cancel()
        searchToken += 1
        let currentToken = searchToken

        Task {
            await performSearch(query: trimmed, token: currentToken)
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        searchToken += 1
        query = ""
        results = []
        errorMessage = nil
        isLoading = false
        lastSubmittedQuery = ""
    }

    private func performSearch(query: String, token: Int) async {
        guard let serverURL = authManager.selectedServerURL,
              let authToken = authManager.authToken else {
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let items = try await networkManager.search(
                serverURL: serverURL,
                authToken: authToken,
                query: query,
                start: 0,
                size: 80
            )

            await MainActor.run {
                guard token == searchToken else { return }
                results = items
                isLoading = false
                errorMessage = nil
                lastSubmittedQuery = query
            }
        } catch {
            await MainActor.run {
                guard token == searchToken else { return }
                results = []
                isLoading = false
                errorMessage = error.localizedDescription
                lastSubmittedQuery = query
            }
        }
    }
}

#if os(tvOS)
private struct SearchableModifier: ViewModifier {
    let isActive: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if isActive {
            content.searchable(text: $query, prompt: "Search movies, shows, and episodes")
        } else {
            content
        }
    }
}
#endif

#Preview {
    PlexSearchView()
        .preferredColorScheme(.dark)
}
