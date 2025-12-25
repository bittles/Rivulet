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

            // Sheet content
            VStack(spacing: 0) {
                // Header with close button
                header
                    .padding(.horizontal, 40)
                    .padding(.top, 30)
                    .padding(.bottom, 16)

                // Channel grid
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(filteredChannels) { channel in
                            PickerChannelCard(
                                channel: channel,
                                isFocused: focusedChannelId == channel.id
                            ) {
                                onSelect(channel)
                            }
                            .focused($focusedChannelId, equals: channel.id)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(white: 0.12))
            )
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .onAppear {
            // Focus the first channel on appear
            if let firstChannel = filteredChannels.first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedChannelId = firstChannel.id
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Channel")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Text("\(availableChannels.count) channels available")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Close button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.6))
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 400, maximum: 500), spacing: 16)
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
            HStack(spacing: 14) {
                // Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(white: 0.2))

                    if let logoURL = channel.logoURL {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(8)
                            default:
                                channelPlaceholder
                            }
                        }
                    } else {
                        channelPlaceholder
                    }
                }
                .frame(width: 70, height: 52)

                // Info - takes all available space
                VStack(alignment: .leading, spacing: 4) {
                    // Channel number and name
                    HStack(spacing: 8) {
                        if let number = channel.channelNumber {
                            Text("\(number)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(minWidth: 30, alignment: .leading)
                        }

                        Text(channel.name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if channel.isHD {
                            Text("HD")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(.white.opacity(0.9))
                                )
                        }
                    }

                    // Program info
                    if let program = currentProgram {
                        Text(program.title)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    } else if let callSign = channel.callSign {
                        Text(callSign)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // Add indicator
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(isFocused ? .green : .white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFocused ? .white.opacity(0.15) : .white.opacity(0.05))
            )
        }
        .buttonStyle(PickerCardButtonStyle(isFocused: isFocused))
    }

    private var channelPlaceholder: some View {
        Image(systemName: "tv")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(.white.opacity(0.3))
    }
}

// MARK: - Picker Card Button Style

private struct PickerCardButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

#Preview {
    ChannelPickerSheet(
        excludedChannelIds: [],
        onSelect: { _ in },
        onDismiss: {}
    )
}
