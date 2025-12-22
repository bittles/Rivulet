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

struct TVSidebarView: View {
    @StateObject private var authManager = PlexAuthManager.shared
    @StateObject private var dataStore = PlexDataStore.shared
    @State private var selectedDestination: TVDestination = .home
    @State private var selectedLibraryKey: String?
    @State private var isSidebarVisible = false
    @FocusState private var focusedItem: String?

    private let sidebarWidth: CGFloat = 400

    var body: some View {
        ZStack {
            // Full-screen content (always visible)
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(0)

            // Dimming overlay when sidebar is visible
            if isSidebarVisible {
                Color.black
                    .opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeSidebar()
                    }
                    .zIndex(1)
            }

            // Sidebar overlay with Liquid Glass
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
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isSidebarVisible)
        .onExitCommand {
            if isSidebarVisible {
                closeSidebar()
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
                    .font(.system(size: 28, weight: .semibold))
                Text("Rivulet")
                    .font(.system(size: 32, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.top, 50)
            .padding(.horizontal, 32)
            .padding(.bottom, 36)

            // Navigation
            ScrollView(.vertical, showsIndicators: false) {
                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 4) {
                        // Home
                        SidebarButton(
                            icon: "house.fill",
                            title: "Home",
                            isSelected: selectedDestination == .home && selectedLibraryKey == nil
                        ) {
                            selectHome()
                        }
                        .focused($focusedItem, equals: "home")

                        // Libraries section
                        if authManager.isAuthenticated && !dataStore.libraries.isEmpty {
                            sectionHeader(authManager.savedServerName?.uppercased() ?? "LIBRARY")

                            ForEach(dataStore.libraries.filter { $0.isVideoLibrary }, id: \.key) { library in
                                SidebarButton(
                                    icon: iconForLibrary(library),
                                    title: library.title,
                                    isSelected: selectedLibraryKey == library.key
                                ) {
                                    selectLibrary(library)
                                }
                                .focused($focusedItem, equals: library.key)
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

                        SidebarButton(
                            icon: "gearshape.fill",
                            title: "Settings",
                            isSelected: selectedDestination == .settings
                        ) {
                            selectSettings()
                        }
                        .focused($focusedItem, equals: "settings")
                    }
                    .padding(.bottom, 50)
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

                Text("Press Menu to open navigation, then go to Settings to connect your Plex server.")
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
        isSidebarVisible = true
        // Focus the currently selected item
        if selectedLibraryKey != nil {
            focusedItem = selectedLibraryKey
        } else if selectedDestination == .settings {
            focusedItem = "settings"
        } else {
            focusedItem = "home"
        }
    }

    private func closeSidebar() {
        isSidebarVisible = false
        focusedItem = nil
    }

    private func selectHome() {
        selectedDestination = .home
        selectedLibraryKey = nil
        closeSidebar()
    }

    private func selectLibrary(_ library: PlexLibrary) {
        selectedLibraryKey = library.key
        selectedDestination = .home
        closeSidebar()
    }

    private func selectSettings() {
        selectedDestination = .settings
        selectedLibraryKey = nil
        closeSidebar()
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
}

// MARK: - Sidebar Button

struct SidebarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))

                Spacer()

                if isSelected {
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(.white.opacity(isFocused || isSelected ? 1.0 : 0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(
                isFocused ? .clear : .identity,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isFocused)
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
    var body: some View {
        NavigationStack {
            List {
                Section("Servers") {
                    NavigationLink {
                        PlexSettingsView()
                    } label: {
                        Label("Plex Server", systemImage: "server.rack")
                    }

                    NavigationLink {
                        IPTVSettingsView()
                    } label: {
                        Label("Live TV Sources", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("App")
                        Spacer()
                        Text("Rivulet")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct PlexSettingsView: View {
    @StateObject private var authManager = PlexAuthManager.shared
    @State private var showAuthSheet = false

    var body: some View {
        List {
            if authManager.isAuthenticated {
                // Connected server section
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(authManager.savedServerName ?? "Plex Server")
                                .font(.headline)

                            if let username = authManager.username {
                                Text("Signed in as \(username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Connected Server")
                }

                // Server URL info
                Section {
                    if let serverURL = authManager.selectedServerURL {
                        HStack {
                            Text("Server URL")
                            Spacer()
                            Text(serverURL)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                } header: {
                    Text("Connection Details")
                }

                // Sign out section
                Section {
                    Button(role: .destructive) {
                        authManager.signOut()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }
            } else {
                // Not connected - show setup option
                Section {
                    VStack(alignment: .center, spacing: 20) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)

                        Text("No Plex Server Connected")
                            .font(.headline)

                        Text("Connect to your Plex server to browse and stream your media library.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            showAuthSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                Text("Connect to Plex")
                            }
                            .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
        .navigationTitle("Plex Server")
        .sheet(isPresented: $showAuthSheet) {
            PlexAuthView()
        }
    }
}

struct IPTVSettingsView: View {
    var body: some View {
        ContentUnavailableView(
            "IPTV Setup",
            systemImage: "antenna.radiowaves.left.and.right",
            description: Text("Dispatcharr and M3U sources will be configured here")
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
