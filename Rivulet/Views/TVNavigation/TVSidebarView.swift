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
    @State private var selectedDestination: TVDestination = .home
    @State private var selectedLibraryKey: String?
    @FocusState private var focusedItem: String?
    @State private var highlightedItem: String = "home"  // Tracks which item is currently highlighted
    @State private var sidebarOpenTime: CFAbsoluteTime = 0  // Track when sidebar opened to ignore stale input

    /// Computed property for sidebar visibility based on active scope
    private var isSidebarVisible: Bool {
        focusScopeManager.isScopeActive(.sidebar)
    }

    private let sidebarWidth: CGFloat = 340

    /// All focusable sidebar item keys in order
    private var allSidebarItems: [String] {
        var items = ["search", "home"]
        items.append(contentsOf: dataStore.visibleMediaLibraries.map { $0.key })
        // Only show Live TV in sidebar if sources are configured
        if liveTVDataStore.hasConfiguredSources {
            items.append("liveTV")
        }
        items.append("settings")
        return items
    }

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
                .animation(.easeOut(duration: 0.15), value: isSidebarVisible)
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
            .animation(.spring(response: 0.18, dampingFraction: 0.9), value: isSidebarVisible)
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
                // Try to verify connection, but load cached data regardless
                async let connectionCheck: () = authManager.verifyAndFixConnection()
                async let hubsLoad: () = dataStore.loadHubsIfNeeded()
                async let librariesLoad: () = dataStore.loadLibrariesIfNeeded()
                _ = await (connectionCheck, hubsLoad, librariesLoad)
            }
        }
        .task {
            // Start background preloading of Live TV data (low priority)
            liveTVDataStore.startBackgroundPreload()
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

            // Navigation - Button-based container that captures focus
            ScrollViewReader { proxy in
                Button {
                    // Select/Enter navigates to highlighted item
                    selectHighlightedItem()
                } label: {
                    ScrollView(.vertical, showsIndicators: false) {
                        GlassEffectContainer {
                            VStack(alignment: .leading, spacing: 4) {
                                // Search
                                SidebarRow(
                                    icon: "magnifyingglass",
                                    title: "Search",
                                    isHighlighted: highlightedItem == "search",
                                    isSelected: selectedDestination == .search
                                )
                                .id("search")

                                // Home
                                SidebarRow(
                                    icon: "house.fill",
                                    title: "Home",
                                    isHighlighted: highlightedItem == "home",
                                    isSelected: selectedDestination == .home && selectedLibraryKey == nil
                                )
                                .id("home")

                                // Libraries section (filtered by visibility, sorted by user order)
                                // Show libraries if user has credentials (even if currently disconnected)
                                if authManager.hasCredentials && !dataStore.visibleMediaLibraries.isEmpty {
                                    sectionHeader(authManager.savedServerName?.uppercased() ?? "LIBRARY")

                                    ForEach(dataStore.visibleMediaLibraries, id: \.key) { library in
                                        SidebarRow(
                                            icon: iconForLibrary(library),
                                            title: library.title,
                                            isHighlighted: highlightedItem == library.key,
                                            isSelected: selectedLibraryKey == library.key
                                        )
                                        .id(library.key)
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

                                // Live TV section (only if sources configured)
                                if liveTVDataStore.hasConfiguredSources {
                                    sectionHeader("LIVE TV")

                                    SidebarRow(
                                        icon: "tv.and.mediabox",
                                        title: "Channels",
                                        isHighlighted: highlightedItem == "liveTV",
                                        isSelected: selectedDestination == .liveTV
                                    )
                                    .id("liveTV")
                                }

                                Spacer(minLength: 60)

                                // Settings
                                Divider()
                                    .background(.white.opacity(0.2))
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 20)

                                SidebarRow(
                                    icon: "gearshape.fill",
                                    title: "Settings",
                                    isHighlighted: highlightedItem == "settings",
                                    isSelected: selectedDestination == .settings
                                )
                                .id("settings")
                            }
                            .padding(.bottom, 50)
                        }
                    }
                }
                .buttonStyle(SidebarContainerButtonStyle())  // Custom style to prevent white focus
                .focused($focusedItem, equals: "sidebar")
                .disabled(!focusScopeManager.isScopeActive(.sidebar))  // Disable when not active (prevents focus escape)
                .focusSection()  // Contain focus within sidebar, prevent escape to content
                .onMoveCommand { direction in
                    handleSidebarNavigation(direction: direction, proxy: proxy)
                }
                .onExitCommand {
                    closeSidebar()
                }
                .onChange(of: isSidebarVisible) { _, isVisible in
                    if isVisible {
                        focusedItem = "sidebar"
                        proxy.scrollTo(highlightedItem, anchor: .center)
                    }
                }
                // Monitor focus changes to ensure sidebar keeps focus when visible
                .onChange(of: focusedItem) { _, newValue in
                    print("🔷 [FOCUS] focusedItem changed to: \(String(describing: newValue)), isSidebarVisible=\(isSidebarVisible)")
                    if isSidebarVisible && newValue != "sidebar" {
                        print("🔷 [FOCUS] ⚠️ Focus escaped sidebar! Re-asserting...")
                        focusedItem = "sidebar"
                    }
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .top)
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
                    .font(.system(size: 36, weight: .semibold))

                Text("Press the Back button or navigate left to open the sidebar, then go to Settings to connect your Plex server.")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation Actions

    private func openSidebar() {
        // Set highlighted item to current selection
        if let libraryKey = selectedLibraryKey {
            highlightedItem = libraryKey
        } else if selectedDestination == .search {
            highlightedItem = "search"
        } else if selectedDestination == .settings {
            highlightedItem = "settings"
        } else if selectedDestination == .liveTV {
            highlightedItem = "liveTV"
        } else {
            highlightedItem = "home"
        }

        // Record open time to ignore stale input that triggered the open
        sidebarOpenTime = CFAbsoluteTimeGetCurrent()

        // Activate sidebar scope (saves content focus automatically)
        focusScopeManager.activate(.sidebar)
    }

    private func closeSidebar() {
        // Deactivate sidebar scope (restores content focus automatically)
        focusScopeManager.deactivate()

        // Delay releasing sidebar focus so content can claim it first
        DispatchQueue.main.async {
            focusedItem = nil
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

    // MARK: - Sidebar Navigation Handler

    private func handleSidebarNavigation(direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        print("🔷 [SIDEBAR NAV] direction=\(direction), isSidebarVisible=\(isSidebarVisible), focusedItem=\(String(describing: focusedItem))")

        // Ignore move commands when sidebar isn't shown
        guard isSidebarVisible else {
            print("🔷 [SIDEBAR NAV] ❌ Ignored - sidebar not visible")
            return
        }

        // Ignore stale input from the gesture that opened the sidebar (within 200ms)
        let timeSinceOpen = CFAbsoluteTimeGetCurrent() - sidebarOpenTime
        if timeSinceOpen < 0.2 {
            print("🔷 [SIDEBAR NAV] ❌ Ignored - stale input")
            return
        }

        let items = allSidebarItems
        guard let currentIndex = items.firstIndex(of: highlightedItem) else {
            print("🔷 [SIDEBAR NAV] ❌ Ignored - highlightedItem not found")
            return
        }

        print("🔷 [SIDEBAR NAV] ✓ Processing: currentIndex=\(currentIndex), highlightedItem=\(highlightedItem)")

        switch direction {
        case .up:
            // Prevent going above first item
            if currentIndex > 0 {
                let newIndex = currentIndex - 1
                highlightedItem = items[newIndex]
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(items[newIndex], anchor: .center)
                }
            }
            // If already at top, do nothing (prevents going off sidebar)
            // Re-assert focus on sidebar to prevent SwiftUI from moving it
            focusedItem = "sidebar"

        case .down:
            // Prevent going below last item
            if currentIndex < items.count - 1 {
                let newIndex = currentIndex + 1
                highlightedItem = items[newIndex]
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(items[newIndex], anchor: .center)
                }
            }
            // If already at bottom, do nothing (prevents going off sidebar)
            // Re-assert focus on sidebar to prevent SwiftUI from moving it
            focusedItem = "sidebar"

        case .right:
            // Navigate to the highlighted item (same as pressing Select)
            selectHighlightedItem()

        case .left:
            // Just close sidebar without navigation
            closeSidebar()

        @unknown default:
            break
        }
    }

    /// Select/navigate to the currently highlighted sidebar item
    private func selectHighlightedItem() {
        // Close first so focus returns to content immediately
        closeSidebar()

        if let library = dataStore.visibleMediaLibraries.first(where: { $0.key == highlightedItem }) {
            navigateToLibrary(library)
        } else if highlightedItem == "search" {
            navigateToSearch()
        } else if highlightedItem == "home" {
            navigateToHome()
        } else if highlightedItem == "liveTV" {
            navigateToLiveTV()
        } else if highlightedItem == "settings" {
            navigateToSettings()
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
