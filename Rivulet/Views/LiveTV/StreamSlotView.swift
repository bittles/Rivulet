//
//  StreamSlotView.swift
//  Rivulet
//
//  Individual player slot for multi-stream view
//

import SwiftUI

struct StreamSlotView: View {
    let slot: MultiStreamViewModel.StreamSlot
    let index: Int
    let isFocused: Bool
    var showBorder: Bool = true
    let onControllerReady: (MPVMetalViewController) -> Void

    @State private var playerController: MPVMetalViewController?
    @State private var lastContainerSize: CGSize = .zero

    private var streamURL: URL? {
        LiveTVDataStore.shared.buildStreamURL(for: slot.channel)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            Color.black

            // MPV Player - use GeometryReader to ensure it fills and updates with container size
            if let url = streamURL {
                GeometryReader { geo in
                    MPVPlayerView(
                        url: url,
                        headers: [:],
                        startTime: nil,
                        delegate: slot.playerWrapper,
                        playerController: $playerController
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .onAppear {
                        updatePlayerSize(geo.size)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        updatePlayerSize(newSize)
                    }
                }
                .transaction { transaction in
                    // Disable animations for the player to prevent layout issues during resize
                    transaction.animation = nil
                }
            }

            // Focus border (only in grid mode)
            if isFocused && showBorder {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 4)
                    .shadow(color: .white.opacity(0.3), radius: 8)
            }

            // Mini channel badge (only in grid mode)
            if showBorder {
                VStack {
                    Spacer()
                    HStack {
                        miniChannelBadge
                        Spacer()
                    }
                }
                .padding(12)

                // Muted indicator (top-right, when not focused)
                if slot.isMuted && !isFocused {
                    VStack {
                        HStack {
                            Spacer()
                            mutedIndicator
                        }
                        Spacer()
                    }
                    .padding(12)
                }
            }

            // Loading/buffering overlay
            if slot.playbackState == .loading || slot.playbackState == .buffering {
                loadingOverlay
            }

            // Error overlay
            if case .failed = slot.playbackState {
                errorOverlay
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: showBorder ? 8 : 0, style: .continuous))
        .onChange(of: playerController) { _, controller in
            if let controller = controller {
                onControllerReady(controller)
                if lastContainerSize != .zero {
                    controller.updateForContainerSize(lastContainerSize)
                }
            }
        }
    }

    private func updatePlayerSize(_ newSize: CGSize) {
        guard newSize != .zero, newSize != lastContainerSize else { return }
        lastContainerSize = newSize
        print("🧩 StreamSlot \(index): container size -> \(newSize)")
        playerController?.updateForContainerSize(newSize)
    }

    // MARK: - Mini Channel Badge

    private var miniChannelBadge: some View {
        HStack(spacing: 8) {
            // Channel logo or icon
            if let logoURL = slot.channel.logoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 24)
                    default:
                        channelIcon
                    }
                }
            } else {
                channelIcon
            }

            // Channel number and name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let number = slot.channel.channelNumber {
                        Text("\(number)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(slot.channel.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                // Current program (if available)
                if let program = slot.currentProgram {
                    Text(program.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black.opacity(0.7))
        )
    }

    private var channelIcon: some View {
        Image(systemName: "tv")
            .font(.system(size: 16))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 24, height: 24)
    }

    // MARK: - Muted Indicator

    private var mutedIndicator: some View {
        Image(systemName: "speaker.slash.fill")
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .padding(8)
            .background(
                Circle()
                    .fill(.black.opacity(0.6))
            )
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)

            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)
        }
    }

    // MARK: - Error Overlay

    private var errorOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)

            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.yellow)

                Text("Stream Error")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    StreamSlotView(
        slot: MultiStreamViewModel.StreamSlot(
            channel: UnifiedChannel(
                id: "test",
                sourceType: .dispatcharr,
                sourceId: "test-source",
                channelNumber: 101,
                name: "Test Channel HD",
                callSign: "TEST",
                logoURL: nil,
                streamURL: URL(string: "http://example.com/stream.m3u8")!,
                tvgId: nil,
                groupTitle: "Entertainment",
                isHD: true
            ),
            playerWrapper: MPVPlayerWrapper(),
            isMuted: false
        ),
        index: 0,
        isFocused: true,
        onControllerReady: { _ in }
    )
    .frame(width: 400, height: 300)
}
