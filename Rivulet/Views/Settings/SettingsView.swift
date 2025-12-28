//
//  SettingsView.swift
//  Rivulet
//
//  Main settings screen for tvOS
//

import SwiftUI

// MARK: - Settings Destination

enum SettingsDestination: Hashable {
    case plex
    case iptv
    case libraries
    case cache
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var navigationPath = NavigationPath()
    @AppStorage("showHomeHero") private var showHomeHero = true
    @AppStorage("showLibraryHero") private var showLibraryHero = true
    @AppStorage("showLibraryRecommendations") private var showLibraryRecommendations = true
    @AppStorage("liveTVLayout") private var liveTVLayoutRaw = LiveTVLayout.channels.rawValue
    @AppStorage("confirmExitMultiview") private var confirmExitMultiview = true
    @Environment(\.focusScopeManager) private var focusScopeManager
    @Environment(\.nestedNavigationState) private var nestedNavState
    @State private var focusTrigger = 0  // Increment to trigger first row focus

    private var liveTVLayout: Binding<LiveTVLayout> {
        Binding(
            get: { LiveTVLayout(rawValue: liveTVLayoutRaw) ?? .channels },
            set: { liveTVLayoutRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    // Header
                    Text("Settings")
                        .font(.system(size: 56, weight: .bold))
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
                                icon: "tv.and.mediabox",
                                iconColor: .blue,
                                title: "Live TV Sources",
                                subtitle: "Manage channel sources"
                            ) {
                                navigationPath.append(SettingsDestination.iptv)
                            }
                        }

                        // Live TV section
                        SettingsSection(title: "Live TV") {
                            SettingsPickerRow(
                                icon: "tv",
                                iconColor: .green,
                                title: "Default Layout",
                                subtitle: "Choose channel grid or TV guide view",
                                selection: liveTVLayout,
                                options: LiveTVLayout.allCases
                            )

                            SettingsToggleRow(
                                icon: "rectangle.split.2x2",
                                iconColor: .blue,
                                title: "Confirm Exit Multiview",
                                subtitle: "Ask before closing multiple streams",
                                isOn: $confirmExitMultiview
                            )
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

                        // Storage section
                        SettingsSection(title: "Storage") {
                            SettingsRow(
                                icon: "internaldrive",
                                iconColor: .gray,
                                title: "Cache & Storage",
                                subtitle: "Manage cached images and data"
                            ) {
                                navigationPath.append(SettingsDestination.cache)
                            }
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
            .onAppear {
                // Set initial focus when view first appears
                DispatchQueue.main.async {
                    focusTrigger += 1
                }
            }
            .onChange(of: focusScopeManager.restoreTrigger) { _, _ in
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
                case .cache:
                    CacheSettingsView(goBack: { navigationPath.removeLast() })
                }
            }
        }
        // Tell parent we're in nested navigation when path is not empty
        .onChange(of: navigationPath.count) { _, newCount in
            let isNested = newCount > 0
            nestedNavState.isNested = isNested
            if isNested {
                nestedNavState.goBackAction = { [weak nestedNavState] in
                    if !navigationPath.isEmpty {
                        navigationPath.removeLast()
                    }
                    if navigationPath.isEmpty {
                        nestedNavState?.isNested = false
                    }
                }
            } else {
                nestedNavState.goBackAction = nil
            }
        }
    }
}

#Preview {
    SettingsView()
}
