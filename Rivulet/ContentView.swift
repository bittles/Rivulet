//
//  ContentView.swift
//  Rivulet
//
//  Created by Bain Gurley on 11/28/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        #if os(tvOS)
        TVSidebarView()
        #else
        NavigationSplitViewContent()
        #endif
    }
}

// MARK: - tvOS Content-First Navigation

#if os(tvOS)

/// Navigation destination for tvOS
enum TVDestination: Hashable, CaseIterable {
    case home
    case settings

    static var allCases: [TVDestination] { [.home, .settings] }
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

struct TVSidebarView: View {
    @StateObject private var authManager = PlexAuthManager.shared
    @StateObject private var dataStore = PlexDataStore.shared
    @State private var selectedDestination: TVDestination = .home
    @State private var selectedLibraryKey: String?
    @State private var isSidebarVisible = false
    @State private var contentFocusVersion = 0
    @FocusState private var focusedItem: String?
    @State private var highlightedItem: String = "home"  // Tracks which item is currently highlighted

    private let sidebarWidth: CGFloat = 340
    
    /// All focusable sidebar item keys in order
    private var allSidebarItems: [String] {
        var items = ["home"]
        items.append(contentsOf: dataStore.visibleVideoLibraries.map { $0.key })
        items.append("settings")
        return items
    }

    var body: some View {
        ZStack {
            // Full-screen content with left-edge trigger
            HStack(spacing: 0) {
                if !isSidebarVisible {
                    LeftEdgeTrigger {
                        openSidebar()
                    }
                }

                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(isSidebarVisible)  // Prevents focus/interaction when sidebar open
                .environment(\.openSidebar, openSidebar)
                .environment(\.contentFocusVersion, contentFocusVersion)
            }
            .zIndex(0)
            .onMoveCommand { direction in
                if direction == .left && !isSidebarVisible {
                    openSidebar()
                }
            }

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
        .onExitCommand(perform: handleExitCommand)
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
                    .font(.system(size: 28, weight: .semibold))
                Text("Rivulet")
                    .font(.system(size: 32, weight: .bold))
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
                                            .font(.system(size: 15))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 16)
                                }

                                Spacer(minLength: 60)

                                // Settings
                                Divider()
                                    .background(.white.opacity(0.15))
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
            .font(.system(size: 12, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.4))
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
                    .id("library-\(library.key)")  // Force instant view recreation on library change
            } else {
                switch selectedDestination {
                case .home:
                    if authManager.isAuthenticated {
                        PlexHomeView()
                    } else {
                        welcomeView
                    }
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
        } else if selectedDestination == .settings {
            highlightedItem = "settings"
        } else {
            highlightedItem = "home"
        }
        
        isSidebarVisible = true
    }

    private func closeSidebar() {
        isSidebarVisible = false
        focusedItem = nil
        contentFocusVersion &+= 1
    }
    
    private func handleExitCommand() {
        print("🟣 [DEBUG] handleExitCommand() called - sidebar visible: \(isSidebarVisible)")
        // Back button (← on remote) toggles sidebar
        // Note: Menu/Home button is a system button we cannot override
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
        } else if highlightedItem == "home" {
            navigateToHome()
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

    private func navigateToLibrary(_ library: PlexLibrary) {
        selectedLibraryKey = library.key
        // Keep destination as .home so library view shows (not .settings)
        selectedDestination = .home
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
        .foregroundStyle(.white.opacity(isHighlighted || isSelected ? 1.0 : 0.7))
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 11)
        .glassEffect(
            isHighlighted ? .regular.tint(.white.opacity(0.15)) : .identity,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            description: Text("IPTV channels will appear here")
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

// MARK: - Settings Views

struct SettingsView: View {
    @State private var navigationPath = NavigationPath()
    @AppStorage("showHomeHero") private var showHomeHero = true
    @AppStorage("showLibraryHero") private var showLibraryHero = true
    @AppStorage("showLibraryRecommendations") private var showLibraryRecommendations = true
    @Environment(\.contentFocusVersion) private var contentFocusVersion
    @State private var focusTrigger = 0  // Increment to trigger first row focus

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    // Header
                    Text("Settings")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 80)
                        .padding(.top, 60)

                    // Settings categories
                    VStack(spacing: 24) {
                        // Servers section
                        SettingsSection(title: "Servers") {
                            SettingsRow(
                                icon: "server.rack",
                                iconColor: .orange,
                                title: "Plex Server",
                                subtitle: "Media library connection",
                                action: {
                                    navigationPath.append(SettingsDestination.plex)
                                },
                                focusTrigger: focusTrigger  // First row gets focus
                            )

                            SettingsRow(
                                icon: "antenna.radiowaves.left.and.right",
                                iconColor: .blue,
                                title: "Live TV Sources",
                                subtitle: "IPTV and Dispatcharr"
                            ) {
                                navigationPath.append(SettingsDestination.iptv)
                            }
                        }

                        // Appearance section
                        SettingsSection(title: "Appearance") {
                            SettingsRow(
                                icon: "sidebar.squares.left",
                                iconColor: .purple,
                                title: "Sidebar Libraries",
                                subtitle: "Show, hide, and reorder libraries"
                            ) {
                                navigationPath.append(SettingsDestination.libraries)
                            }

                            SettingsToggleRow(
                                icon: "sparkles.rectangle.stack",
                                iconColor: .indigo,
                                title: "Home Hero",
                                subtitle: "Featured content banner on Home",
                                isOn: $showHomeHero
                            )

                            SettingsToggleRow(
                                icon: "rectangle.stack",
                                iconColor: .teal,
                                title: "Library Hero",
                                subtitle: "Featured content banner in libraries",
                                isOn: $showLibraryHero
                            )

                            SettingsToggleRow(
                                icon: "square.stack.3d.up",
                                iconColor: .cyan,
                                title: "Discovery Rows",
                                subtitle: "Top Rated, Rediscover, and similar",
                                isOn: $showLibraryRecommendations
                            )
                        }

                        // Playback section (for future use)
                        SettingsSection(title: "Playback") {
                            SettingsRow(
                                icon: "play.rectangle",
                                iconColor: .purple,
                                title: "Video",
                                subtitle: "Quality and streaming options"
                            ) {
                                // Future: Video settings
                            }

                            SettingsRow(
                                icon: "speaker.wave.3",
                                iconColor: .pink,
                                title: "Audio",
                                subtitle: "Sound and language preferences"
                            ) {
                                // Future: Audio settings
                            }
                        }

                        // About section
                        SettingsSection(title: "About") {
                            SettingsInfoRow(title: "App", value: "Rivulet")
                            SettingsInfoRow(title: "Version", value: "1.0.0")
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
                }
            }
            .background(Color.black)
            .onChange(of: contentFocusVersion) { _, _ in
                // Trigger first row to claim focus when sidebar closes
                focusTrigger += 1
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .plex:
                    PlexSettingsView(goBack: { navigationPath.removeLast() })
                case .iptv:
                    IPTVSettingsView(goBack: { navigationPath.removeLast() })
                case .libraries:
                    LibrarySettingsView(goBack: { navigationPath.removeLast() })
                }
            }
        }
    }
}

enum SettingsDestination: Hashable {
    case plex
    case iptv
    case libraries
}

// MARK: - Settings Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 8)

            VStack(spacing: 2) {
                content
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    var focusTrigger: Int? = nil  // When non-nil and changes, claim focus

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isFocused ? .white.opacity(0.15) : .clear)
        )
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            action()
        }
        .onChange(of: focusTrigger) { _, newValue in
            if newValue != nil {
                isFocused = true
            }
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Text(value)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // On/Off text (Apple tvOS Settings style)
            Text(isOn ? "On" : "Off")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isFocused ? .white.opacity(0.15) : .clear)
        )
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            isOn.toggle()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Plex Settings

struct PlexSettingsView: View {
    @StateObject private var authManager = PlexAuthManager.shared
    @State private var showAuthSheet = false
    var goBack: () -> Void = {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                // Header (Menu button on remote navigates back)
                Text("Plex Server")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.top, 60)

                VStack(spacing: 24) {
                    if authManager.isAuthenticated {
                        // Connected server card
                        SettingsSection(title: "Connected Server") {
                            HStack(spacing: 16) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.green.gradient)
                                        .frame(width: 52, height: 52)

                                    Image(systemName: "checkmark")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(authManager.savedServerName ?? "Plex Server")
                                        .font(.system(size: 21, weight: .semibold))
                                        .foregroundStyle(.white)

                                    if let username = authManager.username {
                                        Text("Signed in as \(username)")
                                            .font(.system(size: 15))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }

                        // Connection details
                        if let serverURL = authManager.selectedServerURL {
                            SettingsSection(title: "Connection") {
                                SettingsInfoRow(title: "Server URL", value: serverURL)
                            }
                        }

                        // Sign out
                        SettingsSection(title: "Account") {
                            SettingsActionRow(
                                title: "Sign Out",
                                isDestructive: true
                            ) {
                                authManager.signOut()
                            }
                        }
                    } else {
                        // Not connected
                        VStack(spacing: 28) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 64, weight: .thin))
                                .foregroundStyle(.white.opacity(0.3))

                            VStack(spacing: 8) {
                                Text("No Server Connected")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white)

                                Text("Connect to your Plex server to browse and stream your media library.")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 400)
                            }

                            ConnectButton {
                                showAuthSheet = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .background(Color.black)
        .sheet(isPresented: $showAuthSheet) {
            PlexAuthView()
        }
    }
}

struct SettingsActionRow: View {
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Spacer()
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isDestructive ? .red : .white)
            Spacer()
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isFocused ? (isDestructive ? .red.opacity(0.2) : .white.opacity(0.15)) : .clear)
        )
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            action()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct ConnectButton: View {
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 18, weight: .semibold))
            Text("Connect to Plex")
                .font(.system(size: 18, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .glassEffect(
            isFocused ? .regular.tint(.blue.opacity(0.3)) : .regular,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            action()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - IPTV Settings

struct IPTVSettingsView: View {
    var goBack: () -> Void = {}
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                // Header (Menu button on remote navigates back)
                Text("Live TV Sources")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.top, 60)

                // Placeholder
                VStack(spacing: 28) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 64, weight: .thin))
                        .foregroundStyle(.white.opacity(0.3))

                    VStack(spacing: 8) {
                        Text("Coming Soon")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Dispatcharr and M3U source configuration will be available here.")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .padding(.horizontal, 80)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .background(Color.black)
    }
}

// MARK: - Library Settings

struct LibrarySettingsView: View {
    @StateObject private var dataStore = PlexDataStore.shared
    @StateObject private var librarySettings = LibrarySettingsManager.shared
    var goBack: () -> Void = {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                // Header (Menu button on remote navigates back)
                Text("Sidebar Libraries")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.top, 60)

                Text("Choose which libraries appear in the sidebar. Tap to toggle visibility, use arrows to reorder.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 80)

                if dataStore.libraries.isEmpty {
                    // No libraries
                    VStack(spacing: 28) {
                        Image(systemName: "folder")
                            .font(.system(size: 64, weight: .thin))
                            .foregroundStyle(.white.opacity(0.3))

                        Text("No Libraries")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Connect to a Plex server to manage library visibility.")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 80)
                } else {
                    // Library list
                    VStack(spacing: 24) {
                        SettingsSection(title: "Libraries") {
                            ForEach(orderedLibraries, id: \.key) { library in
                                LibraryVisibilityRow(
                                    library: library,
                                    isVisible: librarySettings.isLibraryVisible(library.key),
                                    onToggle: {
                                        librarySettings.toggleVisibility(for: library.key)
                                    },
                                    onMoveUp: canMoveUp(library) ? { moveUp(library) } : nil,
                                    onMoveDown: canMoveDown(library) ? { moveDown(library) } : nil
                                )
                            }
                        }

                        // Reset button
                        SettingsSection(title: "Reset") {
                            SettingsActionRow(
                                title: "Reset to Defaults",
                                isDestructive: false
                            ) {
                                librarySettings.resetToDefaults()
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
                }
            }
        }
        .background(Color.black)
    }

    // MARK: - Helpers

    /// Libraries sorted by user preference (for display in settings)
    private var orderedLibraries: [PlexLibrary] {
        librarySettings.sortLibraries(dataStore.libraries.filter { $0.isVideoLibrary })
    }

    private func canMoveUp(_ library: PlexLibrary) -> Bool {
        guard let index = orderedLibraries.firstIndex(where: { $0.key == library.key }) else {
            return false
        }
        return index > 0
    }

    private func canMoveDown(_ library: PlexLibrary) -> Bool {
        guard let index = orderedLibraries.firstIndex(where: { $0.key == library.key }) else {
            return false
        }
        return index < orderedLibraries.count - 1
    }

    private func moveUp(_ library: PlexLibrary) {
        guard let orderIndex = librarySettings.libraryOrder.firstIndex(of: library.key) else {
            return
        }
        if orderIndex > 0 {
            librarySettings.moveLibrary(from: orderIndex, to: orderIndex - 1)
        }
    }

    private func moveDown(_ library: PlexLibrary) {
        guard let orderIndex = librarySettings.libraryOrder.firstIndex(of: library.key) else {
            return
        }
        if orderIndex < librarySettings.libraryOrder.count - 1 {
            librarySettings.moveLibrary(from: orderIndex, to: orderIndex + 2)
        }
    }
}

// MARK: - Library Visibility Row

struct LibraryVisibilityRow: View {
    let library: PlexLibrary
    let isVisible: Bool
    let onToggle: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    @FocusState private var isFocused: Bool

    private var iconName: String {
        switch library.type {
        case "movie": return "film.fill"
        case "show": return "tv.fill"
        case "artist": return "music.note"
        case "photo": return "photo.fill"
        default: return "folder.fill"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Reorder controls (always visible, subtle)
            VStack(spacing: 2) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(onMoveUp != nil ? 0.4 : 0.15))
                    .onTapGesture {
                        onMoveUp?()
                    }

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(onMoveDown != nil ? 0.4 : 0.15))
                    .onTapGesture {
                        onMoveDown?()
                    }
            }
            .frame(width: 20)

            // Library icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isVisible ? Color.blue.gradient : Color.gray.opacity(0.3).gradient)
                    .frame(width: 44, height: 44)

                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Library info
            VStack(alignment: .leading, spacing: 2) {
                Text(library.title)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(isVisible ? 1 : 0.5))

                Text(library.type.capitalized)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            // On/Off indicator (Apple tvOS Settings style)
            Text(isVisible ? "On" : "Off")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isFocused ? .white.opacity(0.15) : .clear)
        )
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            onToggle()
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.2), value: isVisible)
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
