//
//  TVSidebarView.swift
//  Rivulet
//
//  Main tvOS sidebar navigation view with sliding glass panel
//

import SwiftUI

#if os(tvOS)

struct TVSidebarView: View {
    @StateObject private var authManager = PlexAuthManager.shared
    @StateObject private var dataStore = PlexDataStore.shared
    @StateObject private var liveTVDataStore = LiveTVDataStore.shared
    @StateObject private var nestedNavState = NestedNavigationState()
    @StateObject private var focusScopeManager = FocusScopeManager()
    @StateObject private var deepLinkHandler = DeepLinkHandler.shared
    @State private var selectedDestination: TVDestination = .home
    @State private var selectedLibraryKey: String?
    @FocusState private var sidebarFocusedItem: String?  // Track focused item in sidebar
    @State private var pendingDestination: TVDestination?
    @State private var pendingLibraryKey: String?

    /// Computed property for sidebar visibility based on active scope
    private var isSidebarVisible: Bool {
        focusScopeManager.isScopeActive(.sidebar)
    }

    private let sidebarWidth: CGFloat = 340

    var body: some View {
        ZStack {
            // Full-screen content with left-edge trigger
            HStack(spacing: 0) {
                // Left-edge trigger - completely removed when guide is active to prevent focus interference
                // Also disabled as fallback in case conditional render has timing issues
                if !focusScopeManager.isScopeActive(.guide) {
                    LeftEdgeTrigger(
                        action: openSidebar,
                        isDisabled: isSidebarVisible || nestedNavState.isNested || focusScopeManager.isScopeActive(.guide)
                    )
                    .opacity(isSidebarVisible || nestedNavState.isNested ? 0 : 1)
                    .allowsHitTesting(!isSidebarVisible && !nestedNavState.isNested && !focusScopeManager.isScopeActive(.guide))
                }

                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Disable content when sidebar visible to prevent focus from escaping
                    .disabled(isSidebarVisible)
                    .environment(\.openSidebar, openSidebar)
                    .environment(\.nestedNavigationState, nestedNavState)
                    .environment(\.isSidebarVisible, isSidebarVisible)
                    .environment(\.focusScopeManager, focusScopeManager)
            }
            .zIndex(0)

            // Dim overlay - animated separately
            Color.black
                .opacity(isSidebarVisible ? 0.4 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isSidebarVisible)
                .onTapGesture {
                    closeSidebar()
                }
                .animation(.easeOut(duration: 0.12), value: isSidebarVisible)
                .zIndex(1)

            HStack(spacing: 0) {
                sidebarContent
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .clipped()
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: 44, style: .continuous)
                    )
                    // GPU-accelerated shadow using blur instead of CPU-rendered .shadow()
                    .background(
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .fill(.black)
                            .blur(radius: 30)
                            .offset(x: 15)
                            .opacity(0.5)
                    )
                    .padding(.leading, 12)
                    .offset(x: isSidebarVisible ? 0 : -sidebarWidth - 60)

                Spacer()
            }
            .zIndex(2)
            .animation(.spring(response: 0.16, dampingFraction: 0.9), value: isSidebarVisible)
        }
        .ignoresSafeArea()
        // Handle exit command based on current state
        .onExitCommand {
            if isSidebarVisible {
                closeSidebar()
            } else if nestedNavState.isNested {
                nestedNavState.goBack()
            } else {
                openSidebar()
            }
        }
        .task(id: authManager.hasCredentials) {
            if authManager.authToken != nil {
                // Verify connection first to avoid 500 errors from stale/invalid server URLs
                await authManager.verifyAndFixConnection()
                // Then load data (will use cache first, then background refresh)
                async let hubsLoad: () = dataStore.loadHubsIfNeeded()
                async let librariesLoad: () = dataStore.loadLibrariesIfNeeded()
                _ = await (hubsLoad, librariesLoad)

                // Start background prefetch of library content for faster navigation
                dataStore.startBackgroundPrefetch()
            }
        }
        .task {
            // Start background preloading of Live TV data (low priority)
            liveTVDataStore.startBackgroundPreload()
        }
        // Handle deep links from Top Shelf
        .onChange(of: deepLinkHandler.pendingPlayback) { _, metadata in
            guard let metadata else { return }
            presentPlayerForDeepLink(metadata)
            deepLinkHandler.pendingPlayback = nil
        }
    }

    // MARK: - Deep Link Player

    /// Present player for a deep link from Top Shelf
    private func presentPlayerForDeepLink(_ metadata: PlexMetadata) {
        // Prefetch loading screen images for instant display
        prefetchPlayerImages(for: metadata)

        let viewModel = UniversalPlayerViewModel(
            metadata: metadata,
            serverURL: authManager.selectedServerURL ?? "",
            authToken: authManager.authToken ?? "",
            startOffset: metadata.viewOffset.map { Double($0) / 1000.0 }
        )

        let playerView = UniversalPlayerView(viewModel: viewModel)
        let container = PlayerContainerViewController(
            rootView: playerView,
            viewModel: viewModel
        )

        // Present from top-most view controller
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            container.modalPresentationStyle = .fullScreen
            topVC.present(container, animated: true)
        }
    }

    /// Prefetch art and poster images for the player loading screen
    private func prefetchPlayerImages(for metadata: PlexMetadata) {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return }

        var urls: [URL] = []

        if let art = metadata.bestArt,
           let url = URL(string: "\(serverURL)\(art)?X-Plex-Token=\(token)") {
            urls.append(url)
        }

        if let thumb = metadata.bestThumb,
           let url = URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(token)") {
            urls.append(url)
        }

        if !urls.isEmpty {
            ImageCacheManager.shared.prefetch(urls: urls)
        }
    }

    // MARK: - Sidebar Content

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App branding
            HStack(spacing: 14) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                Text("Rivulet")
                    .font(.system(size: 34, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.top, 50)
            .padding(.horizontal, 32)
            .padding(.bottom, 36)

            // Navigation with individually focusable items (enables native hold-to-scroll)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    GlassEffectContainer {
                        VStack(alignment: .leading, spacing: 4) {
                            // Search
                            FocusableSidebarRow(
                                id: "search",
                                icon: "magnifyingglass",
                                title: "Search",
                                isSelected: selectedDestination == .search,
                                onSelect: { queueNavigation(destination: .search, libraryKey: nil) },
                                focusedItem: $sidebarFocusedItem
                            )

                            // Home
                            FocusableSidebarRow(
                                id: "home",
                                icon: "house.fill",
                                title: "Home",
                                isSelected: selectedDestination == .home && selectedLibraryKey == nil,
                                onSelect: { queueNavigation(destination: .home, libraryKey: nil) },
                                focusedItem: $sidebarFocusedItem
                            )

                            // Libraries section
                            if authManager.hasCredentials && !dataStore.visibleMediaLibraries.isEmpty {
                                sectionHeader(authManager.savedServerName?.uppercased() ?? "LIBRARY")

                                ForEach(dataStore.visibleMediaLibraries, id: \.key) { library in
                                    FocusableSidebarRow(
                                        id: library.key,
                                        icon: iconForLibrary(library),
                                        title: library.title,
                                        isSelected: selectedLibraryKey == library.key,
                                        onSelect: { queueNavigation(destination: .home, libraryKey: library.key) },
                                        focusedItem: $sidebarFocusedItem
                                    )
                                }
                            }

                            if dataStore.isLoadingLibraries {
                                HStack(spacing: 12) {
                                    ProgressView()
                                        .tint(.white.opacity(0.5))
                                    Text("Loading...")
                                        .font(.system(size: 17))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 32)
                                .padding(.vertical, 16)
                            }

                            // Live TV section
                            if liveTVDataStore.hasConfiguredSources {
                                sectionHeader("LIVE TV")

                                FocusableSidebarRow(
                                    id: "liveTV",
                                    icon: "tv.and.mediabox",
                                    title: "Channels",
                                    isSelected: selectedDestination == .liveTV,
                                    onSelect: { queueNavigation(destination: .liveTV, libraryKey: nil) },
                                    focusedItem: $sidebarFocusedItem
                                )
                            }

                            Spacer(minLength: 60)

                            // Settings
                            Divider()
                                .background(.white.opacity(0.2))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 20)

                            FocusableSidebarRow(
                                id: "settings",
                                icon: "gearshape.fill",
                                title: "Settings",
                                isSelected: selectedDestination == .settings,
                                onSelect: { queueNavigation(destination: .settings, libraryKey: nil) },
                                focusedItem: $sidebarFocusedItem
                            )
                        }
                        .padding(.bottom, 50)
                    }
                }
                .focusSection()
                .disabled(!focusScopeManager.isScopeActive(.sidebar))
                .onExitCommand {
                    closeSidebar()
                }
                .onChange(of: isSidebarVisible) { _, isVisible in
                    if isVisible {
                        // Focus the currently selected item when sidebar opens
                        let itemToFocus = currentSidebarItemId
                        sidebarFocusedItem = itemToFocus
                        proxy.scrollTo(itemToFocus, anchor: .center)
                    } else {
                        sidebarFocusedItem = nil
                        // Apply deferred navigation after the close animation completes
                        applyPendingNavigation()
                    }
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Returns the ID of the currently selected sidebar item
    private var currentSidebarItemId: String {
        if let libraryKey = selectedLibraryKey {
            return libraryKey
        }
        switch selectedDestination {
        case .search: return "search"
        case .home: return "home"
        case .liveTV: return "liveTV"
        case .settings: return "settings"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if let libraryKey = selectedLibraryKey,
               let library = dataStore.libraries.first(where: { $0.key == libraryKey }) {
                PlexLibraryView(libraryKey: library.key, libraryTitle: library.title)
                // Removed .id() to preserve AsyncImage caches across library switches
                // The .task(id: libraryKey) in PlexLibraryView handles data switching
            } else {
                switch selectedDestination {
                case .search:
                    PlexSearchView()
                case .home:
                    // Show PlexHomeView if user has credentials (even if disconnected - will show cache)
                    if authManager.hasCredentials {
                        PlexHomeView()
                    } else {
                        welcomeView
                    }
                case .liveTV:
                    LiveTVContainerView()
                case .settings:
                    SettingsView()
                }
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 28) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.3))

            VStack(spacing: 12) {
                Text("Welcome to Rivulet")
                    .font(.system(size: 46, weight: .semibold))

                Text("Press the Back button or navigate left to open the sidebar, go to Settings, and scroll to the bottom to connect your Plex server.")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation Actions

    /// Queue navigation and close the sidebar; actual navigation applies after close to keep animation smooth
    private func queueNavigation(destination: TVDestination, libraryKey: String?) {
        pendingDestination = destination
        pendingLibraryKey = libraryKey
        closeSidebar()
    }

    private func applyPendingNavigation() {
        guard let destination = pendingDestination else { return }

        // Apply pending navigation now that sidebar is closed
        switch destination {
        case .home:
            if let libraryKey = pendingLibraryKey,
               let library = dataStore.libraries.first(where: { $0.key == libraryKey }) {
                navigateToLibrary(library)
            } else {
                navigateToHome()
            }
        case .search:
            navigateToSearch()
        case .liveTV:
            navigateToLiveTV()
        case .settings:
            navigateToSettings()
        }

        pendingDestination = nil
        pendingLibraryKey = nil
    }

    private func openSidebar() {
        // Activate sidebar scope (saves content focus automatically) with a short spring
        withAnimation(.spring(response: 0.16, dampingFraction: 0.92)) {
            focusScopeManager.activate(.sidebar)
        }
    }

    private func closeSidebar() {
        // Deactivate sidebar scope (restores content focus automatically) with a quick snap
        withAnimation(.easeOut(duration: 0.08)) {
            focusScopeManager.deactivate()
        }
    }

    private func handleExitCommand() {
        // At root level: Menu button toggles sidebar
        if isSidebarVisible {
            closeSidebar()
        } else {
            openSidebar()
        }
    }

    private func iconForLibrary(_ library: PlexLibrary) -> String {
        switch library.type {
        case "movie": return "film.fill"
        case "show": return "tv.fill"
        case "artist": return "music.note"
        case "photo": return "photo.fill"
        default: return "folder.fill"
        }
    }


    // MARK: - Explicit Navigation (on button press or right arrow)

    private func navigateToHome() {
        selectedDestination = .home
        selectedLibraryKey = nil
    }

    private func navigateToSearch() {
        selectedDestination = .search
        selectedLibraryKey = nil
    }

    private func navigateToLibrary(_ library: PlexLibrary) {
        selectedLibraryKey = library.key
        // Keep destination as .home so library view shows (not .settings)
        selectedDestination = .home
    }

    private func navigateToLiveTV() {
        selectedDestination = .liveTV
        selectedLibraryKey = nil
    }

    private func navigateToSettings() {
        selectedDestination = .settings
        selectedLibraryKey = nil
    }
}

#endif
