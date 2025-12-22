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
    @State private var selectedItem: PlexMetadata?
    @State private var heroItem: PlexMetadata?

    var body: some View {
        Group {
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
                // Hero section (not focusable by default)
                if let hero = heroItem {
                    HeroView(
                        item: hero,
                        serverURL: authManager.selectedServerURL ?? "",
                        authToken: authManager.authToken ?? ""
                    ) {
                        selectedItem = hero
                    }
                    .focusable(false) // Don't focus hero by default
                }

                // Content rows
                VStack(alignment: .leading, spacing: 48) {
                    ForEach(Array(dataStore.hubs.enumerated()), id: \.element.id) { index, hub in
                        if let items = hub.Metadata, !items.isEmpty {
                            ContentRow(
                                title: hub.title ?? "Unknown",
                                items: items,
                                serverURL: authManager.selectedServerURL ?? "",
                                authToken: authManager.authToken ?? "",
                                isFirstRow: index == 0,
                                namespace: namespace
                            ) { item in
                                selectedItem = item
                            }
                        }
                    }
                }
                .padding(.top, 48)
                .padding(.bottom, 80)
            }
        }
        #if os(tvOS)
        .ignoresSafeArea(edges: .top)
        .focusScope(namespace)
        #endif
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
    var isFirstRow: Bool = false
    var namespace: Namespace.ID?
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
                        #if os(tvOS)
                        .modifier(DefaultFocusModifier(
                            shouldFocus: isFirstRow && index == 0,
                            namespace: namespace
                        ))
                        #endif
                    }
                }
                .padding(.horizontal, 80)
            }
        }
    }
}

// MARK: - Default Focus Modifier

#if os(tvOS)
struct DefaultFocusModifier: ViewModifier {
    let shouldFocus: Bool
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if shouldFocus, let ns = namespace {
            content.prefersDefaultFocus(in: ns)
        } else {
            content
        }
    }
}
#endif

#Preview {
    PlexHomeView()
        .preferredColorScheme(.dark)
}
