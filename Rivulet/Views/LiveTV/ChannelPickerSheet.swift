//
//  ChannelPickerSheet.swift
//  Rivulet
//
//  Modal sheet for selecting a channel to add to multi-stream view
//

import SwiftUI

struct ChannelPickerSheet: View {
    let excludedChannelIds: Set<String>
    let onSelect: (UnifiedChannel) -> Void
    let onDismiss: () -> Void

    @StateObject private var dataStore = LiveTVDataStore.shared
    @State private var searchText = ""
    @FocusState private var focusedChannelId: String?

    private var availableChannels: [UnifiedChannel] {
        dataStore.channels.filter { !excludedChannelIds.contains($0.id) }
    }

    private var filteredChannels: [UnifiedChannel] {
        if searchText.isEmpty {
            return availableChannels
        }
        let query = searchText.lowercased()
        return availableChannels.filter { channel in
            channel.name.lowercased().contains(query) ||
            (channel.callSign?.lowercased().contains(query) ?? false) ||
            (channel.channelNumber.map { String($0).contains(query) } ?? false)
        }
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Sheet content
            VStack(spacing: 0) {
                // Header
                header
                    .padding(.horizontal, 60)
                    .padding(.top, 50)
                    .padding(.bottom, 24)

                // Channel grid
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(filteredChannels) { channel in
                            PickerChannelCard(
                                channel: channel,
                                isFocused: focusedChannelId == channel.id
                            ) {
                                onSelect(channel)
                            }
                            .focusable()
                            .focused($focusedChannelId, equals: channel.id)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 60)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color(white: 0.1))
                    .ignoresSafeArea()
            )
            .padding(.horizontal, 120)
            .padding(.vertical, 80)
        }
        #if os(tvOS)
        .onExitCommand {
            onDismiss()
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Channel")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)

                Text("\(availableChannels.count) channels available")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Close button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 20)
        ]
    }
}

// MARK: - Picker Channel Card

private struct PickerChannelCard: View {
    let channel: UnifiedChannel
    let isFocused: Bool
    let action: () -> Void

    @StateObject private var dataStore = LiveTVDataStore.shared

    private var currentProgram: UnifiedProgram? {
        dataStore.getCurrentProgram(for: channel)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.2))

                    if let logoURL = channel.logoURL {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(12)
                            default:
                                channelPlaceholder
                            }
                        }
                    } else {
                        channelPlaceholder
                    }
                }
                .frame(width: 80, height: 60)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let number = channel.channelNumber {
                            Text("\(number)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Text(channel.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if channel.isHD {
                            Text("HD")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(.white.opacity(0.8))
                                )
                        }
                    }

                    if let program = currentProgram {
                        Text(program.title)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Add indicator
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(isFocused ? 0.8 : 0.3))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFocused ? .white.opacity(0.2) : .white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isFocused ? .white.opacity(0.5) : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var channelPlaceholder: some View {
        Image(systemName: "tv")
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(.white.opacity(0.3))
    }
}

#Preview {
    ChannelPickerSheet(
        excludedChannelIds: [],
        onSelect: { _ in },
        onDismiss: {}
    )
}
