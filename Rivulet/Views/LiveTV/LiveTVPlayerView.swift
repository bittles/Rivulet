//
//  LiveTVPlayerView.swift
//  Rivulet
//
//  Unified Live TV player supporting 1-4 simultaneous streams
//

import SwiftUI
import Combine

struct LiveTVPlayerView: View {
    @StateObject private var viewModel: MultiStreamViewModel
    @Environment(\.dismiss) private var dismiss

    // Focus management
    @FocusState private var focusArea: FocusArea?

    enum FocusArea: Hashable {
        case streamGrid
        case controlButton(Int)
    }

    init(channel: UnifiedChannel) {
        _viewModel = StateObject(wrappedValue: MultiStreamViewModel(initialChannel: channel))
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Stream grid (or single stream fullscreen)
            streamContent

            // Controls overlay
            if viewModel.showControls {
                controlsOverlay
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }

            // Channel picker
            if viewModel.showChannelPicker {
                ChannelPickerSheet(
                    excludedChannelIds: viewModel.activeChannelIds,
                    onSelect: { channel in
                        Task {
                            await viewModel.addChannel(channel)
                        }
                    },
                    onDismiss: {
                        viewModel.showChannelPicker = false
                    }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        // Don't animate stream count changes - causes issues with MPV player resizing
        #if os(tvOS)
        .onPlayPauseCommand {
            // Physical play/pause button on remote - direct toggle
            viewModel.togglePlayPauseOnFocused()
        }
        .onExitCommand {
            handleExitCommand()
        }
        #endif
        .onChange(of: viewModel.showControls) { _, showControls in
            if showControls {
                // When controls appear, focus the play/pause button (always index 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    focusArea = .controlButton(0)
                }
            } else {
                // When controls hide, focus the stream grid
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusArea = .streamGrid
                }
            }
        }
        .onChange(of: focusArea) { _, newFocus in
            // Reset hide timer when navigating between control buttons
            if case .controlButton = newFocus {
                viewModel.resetControlsTimer()
            }
        }
        .onAppear {
            // Start with controls hidden, focus on stream grid
            viewModel.showControls = false
            focusArea = .streamGrid
        }
        .onDisappear {
            viewModel.stopAllStreams()
        }
    }

    // MARK: - Stream Content

    @ViewBuilder
    private var streamContent: some View {
        if viewModel.streamCount == 1, let slot = viewModel.streams.first {
            // Single stream - fullscreen
            singleStreamView(slot: slot)
        } else {
            // Multiple streams - grid
            streamGrid
        }
    }

    private func singleStreamView(slot: MultiStreamViewModel.StreamSlot) -> some View {
        ZStack {
            StreamSlotView(
                slot: slot,
                index: 0,
                isFocused: false,
                showBorder: false,
                onControllerReady: { controller in
                    viewModel.setPlayerController(controller, for: slot.id)
                }
            )
            .ignoresSafeArea()

            // Invisible focusable area to capture Select press and show controls
            if !viewModel.showControls {
                Color.clear
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($focusArea, equals: .streamGrid)
                    .onLongPressGesture(minimumDuration: 0) {
                        // Select pressed - show controls
                        showControlsWithFocus()
                    }
                    #if os(tvOS)
                    .onMoveCommand { direction in
                        // Single stream: any d-pad press shows controls
                        showControlsWithFocus()
                    }
                    #endif
            }
        }
    }

    private var streamGrid: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 2  // Minimal spacing between videos
            let layout = gridLayout(for: viewModel.streamCount)
            let slotWidth = (geometry.size.width - CGFloat(layout.columns - 1) * spacing) / CGFloat(layout.columns)
            let slotHeight = (geometry.size.height - CGFloat(layout.rows - 1) * spacing) / CGFloat(layout.rows)

            ZStack {
                VStack(spacing: spacing) {
                    ForEach(0..<layout.rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<layout.columns, id: \.self) { col in
                                let index = row * layout.columns + col

                                if index < viewModel.streams.count {
                                    let slot = viewModel.streams[index]

                                    StreamSlotView(
                                        slot: slot,
                                        index: index,
                                        isFocused: viewModel.focusedSlotIndex == index && !viewModel.showControls,
                                        showBorder: viewModel.streamCount > 1,
                                        onControllerReady: { controller in
                                            viewModel.setPlayerController(controller, for: slot.id)
                                        }
                                    )
                                    .frame(width: slotWidth, height: slotHeight)
                                    .clipped()
                                } else {
                                    // Empty slot - same size as other slots, just black
                                    Color.black
                                        .frame(width: slotWidth, height: slotHeight)
                                }
                            }
                        }
                    }
                }

                // Invisible focusable overlay for stream navigation
                if !viewModel.showControls {
                    Color.clear
                        .contentShape(Rectangle())
                        .focusable()
                        .focused($focusArea, equals: .streamGrid)
                        .onLongPressGesture(minimumDuration: 0) {
                            // Select pressed - show controls
                            showControlsWithFocus()
                        }
                        #if os(tvOS)
                        .onMoveCommand { direction in
                            handleStreamNavigation(direction)
                        }
                        #endif
                }
            }
        }
    }

    private func gridLayout(for count: Int) -> (rows: Int, columns: Int) {
        switch count {
        case 0, 1:
            return (1, 1)
        case 2:
            return (1, 2)  // Side by side
        case 3, 4:
            return (2, 2)  // 2x2 grid (3 streams = 3 videos + 1 black space)
        default:
            return (2, 2)
        }
    }

    // MARK: - Stream Navigation (when controls hidden)

    #if os(tvOS)
    private func handleStreamNavigation(_ direction: MoveCommandDirection) {
        guard !viewModel.showControls else { return }

        // Multi-stream: d-pad navigates between streams
        if viewModel.streamCount > 1 {
            let layout = gridLayout(for: viewModel.streamCount)
            let currentIndex = viewModel.focusedSlotIndex
            let row = currentIndex / layout.columns
            let col = currentIndex % layout.columns

            var newIndex = currentIndex

            switch direction {
            case .left:
                if col > 0 {
                    newIndex = currentIndex - 1
                }
                // At left edge - do nothing

            case .right:
                if col < layout.columns - 1 && currentIndex + 1 < viewModel.streamCount {
                    newIndex = currentIndex + 1
                }
                // At right edge - do nothing

            case .up:
                if row > 0 {
                    let upIndex = currentIndex - layout.columns
                    if upIndex >= 0 {
                        newIndex = upIndex
                    }
                }
                // At top edge - do nothing (no controls popup from d-pad)

            case .down:
                if row < layout.rows - 1 {
                    let downIndex = currentIndex + layout.columns
                    if downIndex < viewModel.streamCount {
                        newIndex = downIndex
                    }
                }
                // At bottom edge - do nothing

            @unknown default:
                break
            }

            if newIndex != currentIndex {
                viewModel.setFocus(to: newIndex)
            }
        }
        // Single stream: Select shows controls (handled by Button action)
    }
    #endif

    private func showControlsWithFocus() {
        withAnimation(.easeInOut(duration: 0.25)) {
            viewModel.showControlsTemporarily()
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        ZStack {
            // Gradient backgrounds
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.8), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            }
            .ignoresSafeArea()

            VStack {
                // Top bar - focused channel info
                topBar
                    .padding(.horizontal, 60)
                    .padding(.top, 50)

                Spacer()

                // Bottom controls
                bottomControls
                    .padding(.bottom, 60)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            if let focusedStream = viewModel.focusedStream {
                // Channel logo
                if let logoURL = focusedStream.channel.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 60)
                        default:
                            channelIcon
                        }
                    }
                } else {
                    channelIcon
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        if let number = focusedStream.channel.channelNumber {
                            Text("\(number)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Text(focusedStream.channel.name)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)

                        if focusedStream.channel.isHD {
                            Text("HD")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.white)
                                )
                        }

                        // Live indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                            Text("LIVE")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.red)
                        }
                    }

                    if let program = focusedStream.currentProgram {
                        Text(program.title)
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.8))

                        Text(programTimeString(program))
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                // Stream count indicator (only show when multiple streams)
                if viewModel.streamCount > 1 {
                    streamCountBadge
                }
            }
        }
    }

    private var channelIcon: some View {
        Image(systemName: "tv")
            .font(.system(size: 32))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 80, height: 60)
    }

    private var streamCountBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.7))

            Text("\(viewModel.streamCount)/4")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.15))
        )
    }

    private var bottomControls: some View {
        HStack(spacing: 32) {
            let buttons = buildControlButtons()

            ForEach(Array(buttons.enumerated()), id: \.offset) { index, button in
                PlayerControlButton(
                    icon: button.icon,
                    label: button.label,
                    isLarge: button.isLarge,
                    isFocused: focusArea == .controlButton(index),
                    action: button.action
                )
                .focused($focusArea, equals: .controlButton(index))
            }
        }
    }

    private struct ControlButtonConfig {
        let icon: String
        let label: String
        var isLarge: Bool = false
        let action: () -> Void
    }

    private func buildControlButtons() -> [ControlButtonConfig] {
        var buttons: [ControlButtonConfig] = []

        // Play/Pause button (always first on left)
        let isPlaying = viewModel.focusedStream?.playerWrapper.isPlaying ?? false
        buttons.append(ControlButtonConfig(
            icon: isPlaying ? "pause.fill" : "play.fill",
            label: isPlaying ? "Pause" : "Play",
            isLarge: true,
            action: { viewModel.togglePlayPauseOnFocused() }
        ))

        // Remove stream button (only when multiple streams)
        if viewModel.streamCount > 1 {
            buttons.append(ControlButtonConfig(
                icon: "minus.circle.fill",
                label: "Remove",
                action: {
                    print("📺 Remove pressed: focusedSlotIndex=\(viewModel.focusedSlotIndex), streamCount=\(viewModel.streamCount)")
                    for (idx, stream) in viewModel.streams.enumerated() {
                        print("  - Stream \(idx): \(stream.channel.name) (focused: \(idx == viewModel.focusedSlotIndex))")
                    }
                    viewModel.removeStream(at: viewModel.focusedSlotIndex)
                    // If only 1 stream left, hide controls
                    if viewModel.streamCount <= 1 {
                        viewModel.showControls = false
                    }
                }
            ))
        }

        // Add channel button (next to Remove)
        if viewModel.canAddStream {
            buttons.append(ControlButtonConfig(
                icon: "plus.circle.fill",
                label: "Add Stream",
                action: { viewModel.showChannelPicker = true }
            ))
        }

        // Exit button (always last on right)
        buttons.append(ControlButtonConfig(
            icon: "xmark.circle.fill",
            label: "Exit",
            action: { dismissPlayer() }
        ))

        return buttons
    }

    // MARK: - Helpers

    private func programTimeString(_ program: UnifiedProgram) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let start = formatter.string(from: program.startTime)
        let end = formatter.string(from: program.endTime)
        return "\(start) - \(end)"
    }

    #if os(tvOS)
    private func handleExitCommand() {
        if viewModel.showChannelPicker {
            viewModel.showChannelPicker = false
        } else if viewModel.showControls {
            // Hide controls and return focus to stream grid
            withAnimation(.easeOut(duration: 0.2)) {
                viewModel.showControls = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusArea = .streamGrid
            }
        } else {
            dismissPlayer()
        }
    }
    #endif

    private func dismissPlayer() {
        viewModel.stopAllStreams()
        dismiss()
    }
}

// MARK: - Player Control Button

private struct PlayerControlButton: View {
    let icon: String
    let label: String
    var isLarge: Bool = false
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isFocused ? .white.opacity(0.4) : .white.opacity(0.2))
                        .frame(width: isLarge ? 80 : 64, height: isLarge ? 80 : 64)

                    Image(systemName: icon)
                        .font(.system(size: isLarge ? 36 : 28))
                        .foregroundStyle(.white)
                }

                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isFocused ? .white : .white.opacity(0.7))
            }
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(PlayerButtonStyle())
    }
}

// MARK: - Player Button Style

private struct PlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

#Preview {
    LiveTVPlayerView(channel: UnifiedChannel(
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
    ))
}
