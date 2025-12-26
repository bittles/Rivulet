//
//  LiveTVContainerView.swift
//  Rivulet
//
//  Container view that switches between Channel Layout and Guide Layout
//  based on user settings
//

import SwiftUI

// MARK: - Live TV Layout Option

enum LiveTVLayout: String, CaseIterable, CustomStringConvertible {
    case channels = "Channels"
    case guide = "Guide"

    var description: String { rawValue }
}

// MARK: - Live TV Container View

struct LiveTVContainerView: View {
    @AppStorage("liveTVLayout") private var liveTVLayoutRaw = "Channels"
    @StateObject private var dataStore = LiveTVDataStore.shared

    private var layout: LiveTVLayout {
        LiveTVLayout(rawValue: liveTVLayoutRaw) ?? .channels
    }

    var body: some View {
        Group {
            switch layout {
            case .channels:
                ChannelListView()
            case .guide:
                GuideLayoutView()
            }
        }
        .task {
            // Elevate EPG loading priority when user visits Live TV
            await dataStore.elevatePreloadPriority()
        }
    }
}

#Preview {
    LiveTVContainerView()
}
