//
//  ChannelListView.swift
//  Rivulet
//
//  Live TV channel list view
//

import SwiftUI

struct ChannelListView: View {
    @StateObject private var dataStore = LiveTVDataStore.shared
    @State private var searchText = ""
    @State private var selectedChannel: UnifiedChannel?
    @State private var multiViewChannel: UnifiedChannel?

    private var filteredChannels: [UnifiedChannel] {
        if searchText.isEmpty {
            return dataStore.channels
        }
        let query = searchText.lowercased()
        return dataStore.channels.filter { channel in
            channel.name.lowercased().contains(query) ||
            (channel.callSign?.lowercased().contains(query) ?? false) ||
            (channel.channelNumber.map { String($0).contains(query) } ?? false)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if dataStore.isLoadingChannels && dataStore.channels.isEmpty {
                loadingView
            } else if dataStore.channels.isEmpty {
                emptyView
            } else {
                channelGrid
            }
        }
        .task {
            // Load channels if not already loaded
            if dataStore.channels.isEmpty && !dataStore.isLoadingChannels {
                await dataStore.loadChannels()
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading channels...")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "tv.slash")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(.white.opacity(0.3))

            VStack(spacing: 12) {
                Text("No Channels")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Add a Live TV source in Settings to see channels here.")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
        }
    }

    // MARK: - Channel Grid

    private var channelGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    Text("Live TV")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white)

                    Text("\(dataStore.channels.count) channels available")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 80)
                .padding(.top, 60)

                // Channel grid
                LazyVGrid(columns: gridColumns, spacing: 24) {
                    ForEach(filteredChannels) { channel in
                        ChannelCard(
                            channel: channel,
                            onTap: {
                                selectedChannel = channel
                            },
                            onMultiView: {
                                multiViewChannel = channel
                            }
                        )
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .fullScreenCover(item: $selectedChannel) { channel in
            LiveTVPlayerView(channel: channel)
        }
        .fullScreenCover(item: $multiViewChannel) { channel in
            MultiStreamPlayerView(initialChannel: channel)
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 24)
        ]
    }
}

// MARK: - Channel Card

struct ChannelCard: View {
    let channel: UnifiedChannel
    let onTap: () -> Void
    let onMultiView: () -> Void

    @FocusState private var isFocused: Bool
    @StateObject private var dataStore = LiveTVDataStore.shared

    private var currentProgram: UnifiedProgram? {
        dataStore.getCurrentProgram(for: channel)
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            cardContent
        }
        .buttonStyle(ChannelCardButtonStyle(isFocused: isFocused))
        .focused($isFocused)
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Watch", systemImage: "play.fill")
            }

            Button {
                onMultiView()
            } label: {
                Label("Open in Multi-View", systemImage: "rectangle.split.2x2")
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo area
            ZStack {
                Rectangle()
                    .fill(Color(white: 0.15))

                if let logoURL = channel.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(20)
                        case .failure:
                            channelPlaceholder
                        case .empty:
                            ProgressView()
                        @unknown default:
                            channelPlaceholder
                        }
                    }
                } else {
                    channelPlaceholder
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Channel info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    if let number = channel.channelNumber {
                        Text("\(number)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text(channel.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if channel.isHD {
                        Text("HD")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(.white.opacity(0.8))
                            )
                    }
                }

                if let program = currentProgram {
                    Text(program.title)
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                } else if let callSign = channel.callSign {
                    Text(callSign)
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isFocused ? .white.opacity(0.15) : .white.opacity(0.05))
        )
    }

    private var channelPlaceholder: some View {
        Image(systemName: "tv")
            .font(.system(size: 40, weight: .light))
            .foregroundStyle(.white.opacity(0.3))
    }
}

// MARK: - Channel Card Button Style

private struct ChannelCardButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 20, y: 10)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

#Preview {
    ChannelListView()
}
