//
//  ContentView.swift
//  Rivulet
//
//  Created by Bain Gurley on 11/28/25.
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        #if os(tvOS)
        TVSidebarView()
            .preferredColorScheme(.dark)  // Force dark mode on tvOS
        #else
        NavigationSplitViewContent()
        #endif
    }
}

// MARK: - tvOS Content-First Navigation

#if os(tvOS)

/// Navigation destination for tvOS
enum TVDestination: Hashable, CaseIterable {
    case search
    case home
    case liveTV
    case settings

    static var allCases: [TVDestination] { [.search, .home, .liveTV, .settings] }
}

/// Environment key for opening sidebar from content views
struct OpenSidebarAction: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openSidebar: () -> Void {
        get { self[OpenSidebarAction.self] }
        set { self[OpenSidebarAction.self] = newValue }
    }
}

/// Environment key used to request content to claim focus after sidebar closes
struct ContentFocusVersionKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

extension EnvironmentValues {
    var contentFocusVersion: Int {
        get { self[ContentFocusVersionKey.self] }
        set { self[ContentFocusVersionKey.self] = newValue }
    }
}

/// Preference key for nested navigation state (bubbles up from child views)
struct IsInNestedNavigationKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()  // True if any child is in nested nav
    }
}

/// Observable object to track nested navigation state across views
@MainActor
class NestedNavigationState: ObservableObject {
    @Published var isNested: Bool = false

    /// Action to go back from nested navigation (set by child views)
    var goBackAction: (() -> Void)?

    func goBack() {
        goBackAction?()
    }
}

/// Environment key for nested navigation state
private struct NestedNavigationStateKey: EnvironmentKey {
    static let defaultValue: NestedNavigationState = NestedNavigationState()
}

extension EnvironmentValues {
    var nestedNavigationState: NestedNavigationState {
        get { self[NestedNavigationStateKey.self] }
        set { self[NestedNavigationStateKey.self] = newValue }
    }
}

struct TVSidebarView: View {
    @StateObject private var authManager = PlexAuthManager.shared
    @StateObject private var dataStore = PlexDataStore.shared
    @StateObject private var liveTVDataStore = LiveTVDataStore.shared
    @StateObject private var nestedNavState = NestedNavigationState()
    @State private var selectedDestination: TVDestination = .home
    @State private var selectedLibraryKey: String?
    @State private var isSidebarVisible = false
    @State private var contentFocusVersion = 0
    @FocusState private var focusedItem: String?
    @State private var highlightedItem: String = "home"  // Tracks which item is currently highlighted

    private let sidebarWidth: CGFloat = 340
    
    /// All focusable sidebar item keys in order
    private var allSidebarItems: [String] {
        var items = ["search", "home"]
        items.append(contentsOf: dataStore.visibleVideoLibraries.map { $0.key })
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
                // Only show left-edge trigger when not in nested navigation
                if !isSidebarVisible && !nestedNavState.isNested {
                    LeftEdgeTrigger {
                        openSidebar()
                    }
                }

                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(isSidebarVisible)  // Prevents focus/interaction when sidebar open
                .environment(\.openSidebar, openSidebar)
                .environment(\.contentFocusVersion, contentFocusVersion)
                .environment(\.nestedNavigationState, nestedNavState)
            }
            .zIndex(0)

            if isSidebarVisible {
                Color.black
                    .opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeSidebar()
                    }
                    .zIndex(1)
            }

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
                    .shadow(color: .black.opacity(0.5), radius: 40, x: 20, y: 0)
                    .padding(.leading, 12)
                    .offset(x: isSidebarVisible ? 0 : -sidebarWidth - 60)

                Spacer()
            }
            .zIndex(2)
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.2), value: isSidebarVisible)
        // Handle exit command based on current state
        .onExitCommand {
            if isSidebarVisible {
                closeSidebar()
            } else if nestedNavState.isNested {
                // Go back from nested navigation
                nestedNavState.goBack()
            } else {
                openSidebar()
            }
        }
        .task(id: authManager.isAuthenticated) {
            if authManager.authToken != nil {
                await authManager.verifyAndFixConnection()
                if authManager.isAuthenticated {
                    async let hubsLoad: () = dataStore.loadHubsIfNeeded()
                    async let librariesLoad: () = dataStore.loadLibrariesIfNeeded()
                    _ = await (hubsLoad, librariesLoad)
                }
            }
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
                                if authManager.isAuthenticated && !dataStore.visibleVideoLibraries.isEmpty {
                                    sectionHeader(authManager.savedServerName?.uppercased() ?? "LIBRARY")

                                    ForEach(dataStore.visibleVideoLibraries, id: \.key) { library in
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
                .onMoveCommand { direction in
                    handleSidebarNavigation(direction: direction, proxy: proxy)
                }
                .onExitCommand {
                    // Menu button closes sidebar when it's focused
                    closeSidebar()
                }
                .onChange(of: isSidebarVisible) { _, isVisible in
                    if isVisible {
                        // When sidebar becomes visible, capture focus immediately
                        DispatchQueue.main.async {
                            focusedItem = "sidebar"
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(highlightedItem, anchor: .center)
                            }
                        }
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
                    if authManager.isAuthenticated {
                        PlexHomeView()
                    } else {
                        welcomeView
                    }
                case .liveTV:
                    ChannelListView()
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

        isSidebarVisible = true
    }

    private func closeSidebar() {
        // First: tell content to prepare to claim focus
        contentFocusVersion &+= 1

        // Then: hide sidebar
        isSidebarVisible = false

        // Delay releasing sidebar focus so content can claim it first
        // This prevents the system from picking a random focus target
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
        // Ignore move commands when sidebar isn't shown
        guard isSidebarVisible else { return }

        let items = allSidebarItems
        guard let currentIndex = items.firstIndex(of: highlightedItem) else { return }
        
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

        if let library = dataStore.visibleVideoLibraries.first(where: { $0.key == highlightedItem }) {
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

        // Ask content to reclaim focus after sidebar closes
        contentFocusVersion &+= 1
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

// MARK: - Sidebar Button

struct SidebarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var onFocusChange: ((Bool) -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 24)

            Text(title)
                .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 4)

            if isSelected {
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
            }
        }
        .foregroundStyle(.white.opacity(isFocused || isSelected ? 1.0 : 0.7))
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 11)
        .glassEffect(
            isFocused ? .regular.tint(.white.opacity(0.15)) : .identity,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .padding(.horizontal, 16)
        .focusable()
        .focused($isFocused)
        .onChange(of: isFocused) { _, newValue in
            // Navigate immediately when focus is gained
            // This happens instantly with cached data
            if newValue {
                onFocusChange?(newValue)
            }
        }
        .onTapGesture {
            // Tap just closes sidebar - navigation already happened on focus
            action()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Left Edge Trigger (opens sidebar when focus reaches left edge)

struct LeftEdgeTrigger: View {
    let action: () -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button {
            action()
        } label: {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 32)
                .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onChange(of: isFocused) { _, newValue in
            if newValue {
                action()
            }
        }
    }
}

// MARK: - Conditional Exit Command Modifier

/// Conditionally attaches onExitCommand only when sidebar is visible
struct SidebarExitCommand: ViewModifier {
    let isSidebarVisible: Bool
    let closeAction: () -> Void

    func body(content: Content) -> some View {
        if isSidebarVisible {
            content.onExitCommand(perform: closeAction)
        } else {
            content
        }
    }
}

extension View {
    func ifSidebarVisible(_ isVisible: Bool, close: @escaping () -> Void) -> some View {
        self.modifier(SidebarExitCommand(isSidebarVisible: isVisible, closeAction: close))
    }
}

// MARK: - Sidebar Container Button Style (no focus highlight)

struct SidebarContainerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
        // No visual changes on focus or press - we handle highlighting manually via SidebarRow
    }
}

// MARK: - Sidebar Row (non-focusable, for use with single-focus sidebar)

struct SidebarRow: View {
    let icon: String
    let title: String
    let isHighlighted: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 26)

            Text(title)
                .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 4)

            if isSelected {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
            }
        }
        .foregroundStyle(.white.opacity(isHighlighted || isSelected ? 1.0 : 0.6))
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHighlighted ? .white.opacity(0.15) : .clear)
        )
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.15), value: isHighlighted)
    }
}

#endif

// MARK: - macOS/iOS Split View Navigation

struct NavigationSplitViewContent: View {
    @State private var selectedSection: SidebarSection? = .settings

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedSection: $selectedSection)
        } detail: {
            switch selectedSection {
            case .plexSearch:
                PlexSearchView()
            case .plexHome:
                PlexHomeView()
            case .plexLibrary(let key, let title):
                PlexLibraryView(libraryKey: key, libraryTitle: title)
            case .liveTVChannels:
                ChannelListView()
            case .liveTVGuide:
                EPGGridView()
            case .settings:
                SettingsView()
            case .none:
                ContentUnavailableView(
                    "Select a Section",
                    systemImage: "tv",
                    description: Text("Choose from the sidebar to get started")
                )
            }
        }
    }
}

// MARK: - Placeholder Views (to be implemented in Phase 5)

struct ChannelListView: View {
    var body: some View {
        ContentUnavailableView(
            "Channels",
            systemImage: "tv",
            description: Text("Live TV channels will appear here")
        )
    }
}

struct EPGGridView: View {
    var body: some View {
        ContentUnavailableView(
            "TV Guide",
            systemImage: "calendar",
            description: Text("Electronic Program Guide will appear here")
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            ServerConfiguration.self,
            PlexServer.self,
            IPTVSource.self,
            Channel.self,
            FavoriteChannel.self,
            WatchProgress.self,
            EPGProgram.self,
        ], inMemory: true)
}
