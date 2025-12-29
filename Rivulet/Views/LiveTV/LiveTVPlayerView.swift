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
    @AppStorage("confirmExitMultiview") private var confirmExitMultiview = true
    @State private var showExitConfirmation = false
    @State private var showChannelBadges = true
    @State private var channelBadgeTimer: Timer?

    // Dismiss callback - used instead of @Environment(\.dismiss) since we use ZStack overlay
    private let onDismiss: () -> Void

    // Focus management
    @FocusState private var focusArea: FocusArea?

    enum FocusArea: Hashable {
        case streamGrid
        case controlButton(Int)
        case exitConfirmButton(Int)
    }

    init(channel: UnifiedChannel, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: MultiStreamViewModel(initialChannel: channel))
        self.onDismiss = onDismiss
    }

    @Namespace private var playerFocusNamespace

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            // Stream grid (or single stream fullscreen)
            // Transaction prevents animations from affecting player views when state changes
            streamContent
                .transaction { transaction in
                    transaction.animation = nil
                }

            // Controls overlay
            if viewModel.showControls {
                controlsOverlay
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }

            // Channel picker (for adding or replacing streams)
            if viewModel.showChannelPicker {
                // When replacing, don't exclude the current channel (user might want to re-select it)
                let excludedIds: Set<String> = {
                    if viewModel.replaceSlotIndex != nil,
                       let currentId = viewModel.focusedStream?.channel.id {
                        return viewModel.activeChannelIds.subtracting([currentId])
                    }
                    return viewModel.activeChannelIds
                }()
                ChannelPickerSheet(
                    excludedChannelIds: excludedIds,
                    onSelect: { channel in
                        Task {
                            if let replaceIndex = viewModel.replaceSlotIndex {
                                // Replace the stream at the specified index
                                await viewModel.replaceStream(at: replaceIndex, with: channel)
                            } else {
                                // Add a new stream
                                await viewModel.addChannel(channel)
                            }
                        }
                    },
                    onDismiss: {
                        viewModel.showChannelPicker = false
                        viewModel.replaceSlotIndex = nil
                    }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }

            // Exit confirmation overlay
            if showExitConfirmation {
                exitConfirmationOverlay
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .focusScope(playerFocusNamespace)
        .focusSection()
        .defaultFocus($focusArea, .streamGrid)
        .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        .animation(.easeInOut(duration: 0.25), value: showChannelBadges)
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
        .onChange(of: viewModel.focusedSlotIndex) { _, _ in
            // Show channel badges briefly when switching focused stream in multiview
            if viewModel.streamCount > 1 {
                showChannelBadgesTemporarily()
            }
        }
        .onChange(of: viewModel.showControls) { _, showControls in
            // Show/hide badges with controls
            if showControls {
                channelBadgeTimer?.invalidate()
                withAnimation(.easeInOut(duration: 0.25)) {
                    showChannelBadges = true
                }
            } else {
                // Start hide timer when controls hide
                showChannelBadgesTemporarily()
            }
        }
        .onAppear {
            print("📺 LiveTVPlayerView onAppear")
            // Start with controls hidden, focus on stream grid
            viewModel.showControls = false
            // Delay focus grab slightly to ensure view is laid out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("📺 LiveTVPlayerView setting focusArea to .streamGrid")
                focusArea = .streamGrid
            }
            // Show badges initially then auto-hide
            showChannelBadgesTemporarily()
        }
        .onChange(of: focusArea) { oldValue, newValue in
            print("📺 focusArea changed: \(String(describing: oldValue)) → \(String(describing: newValue))")
        }
        .onDisappear {
            channelBadgeTimer?.invalidate()
            // Only stop streams if we're actually exiting (not showing confirmation)
            if !showExitConfirmation {
                viewModel.stopAllStreams()
            }
        }
        .onChange(of: showExitConfirmation) { _, show in
            if show {
                // Focus the Cancel button (index 0) when confirmation appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusArea = .exitConfirmButton(0)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showExitConfirmation)
    }

    // MARK: - Stream Content

    // Always use streamGrid for all stream counts (1-4) to prevent view hierarchy
    // destruction when transitioning from 1 to 2 streams. The grid layout handles
    // single streams as a 1x1 fullscreen layout.
    private var streamContent: some View {
        streamGrid
    }

    private var streamGrid: some View {
        GeometryReader { geometry in
            let frames = layoutFrames(for: geometry.size)

            ZStack(alignment: .topLeading) {
                ForEach(Array(viewModel.streams.enumerated()), id: \.element.id) { index, slot in
                    if let rect = frames[slot.id] {
                        StreamSlotView(
                            slot: slot,
                            index: index,
                            isFocused: viewModel.focusedSlotIndex == index && !viewModel.showControls,
                            showBorder: viewModel.streamCount > 1,
                            showChannelBadge: showChannelBadges,
                            onControllerReady: { controller in
                                viewModel.setPlayerController(controller, for: slot.id)
                            }
                        )
                        .id(slot.id)
                        .frame(width: rect.width, height: rect.height)
                        .clipped()
                        .position(x: rect.midX, y: rect.midY)
                        // Prevent animations from affecting this stream when others change
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                    }
                }
            }
            // Disable animations on the entire grid when stream count changes
            .transaction { transaction in
                transaction.animation = nil
            }

            // Invisible focusable overlay for stream navigation
            if !viewModel.showControls && !showExitConfirmation {
                Color.clear
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($focusArea, equals: .streamGrid)
                    .prefersDefaultFocus(in: playerFocusNamespace)
                    .onTapGesture {
                        // Select pressed - show controls
                        showControlsWithFocus()
                    }
                    #if os(tvOS)
                    .onMoveCommand { direction in
                        handleStreamNavigation(direction)
                    }
                    .onExitCommand {
                        handleExitCommand()
                    }
                    #endif
            }
        }
        .ignoresSafeArea()
    }

    private func layoutFrames(for size: CGSize) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]

        // Single stream: use full screen, no spacing or aspect ratio constraints
        // (MPV handles letterboxing internally)
        if viewModel.streamCount == 1, let slot = viewModel.streams.first {
            frames[slot.id] = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            return frames
        }

        let spacing: CGFloat = 8
        let aspect: CGFloat = 16.0 / 9.0

        if case .focus(let mainId) = viewModel.layoutMode, viewModel.streamCount > 1 {
            let mainSlot = viewModel.streams.first(where: { $0.id == mainId }) ?? viewModel.streams.first
            let sideStreams = viewModel.streams.filter { $0.id != mainSlot?.id }
            let sideCount = max(sideStreams.count, 1)

            // Main stream: 75% width, maintain 16:9 aspect ratio
            let mainWidth = size.width * 0.75
            let mainHeight = min(mainWidth / aspect, size.height)
            let actualMainWidth = mainHeight * aspect  // Recalculate if height-constrained

            // Side streams: remaining width, stacked vertically with 16:9 aspect
            let sideWidth = size.width - actualMainWidth - spacing * 2
            let sideSlotHeight = sideWidth / aspect
            let totalSideHeight = sideSlotHeight * CGFloat(sideCount) + spacing * CGFloat(sideCount - 1)

            // Center everything vertically
            let mainY = (size.height - mainHeight) / 2
            let sideStartY = (size.height - totalSideHeight) / 2

            // Center everything horizontally
            let totalWidth = actualMainWidth + spacing + sideWidth
            let startX = (size.width - totalWidth) / 2

            if let mainSlot {
                frames[mainSlot.id] = CGRect(x: startX, y: mainY, width: actualMainWidth, height: mainHeight)
            }

            var currentY = sideStartY
            for slot in sideStreams {
                frames[slot.id] = CGRect(x: startX + actualMainWidth + spacing, y: currentY, width: sideWidth, height: sideSlotHeight)
                currentY += sideSlotHeight + spacing
            }
        } else {
            let layout = gridLayout(for: viewModel.streamCount)
            let availableWidth = size.width - CGFloat(layout.columns - 1) * spacing
            let availableHeight = size.height - CGFloat(layout.rows - 1) * spacing
            let slotWidth = availableWidth / CGFloat(layout.columns)
            let maxRowHeight = availableHeight / CGFloat(layout.rows)
            let slotHeight = min(slotWidth / aspect, maxRowHeight)
            let totalHeight = slotHeight * CGFloat(layout.rows) + spacing * CGFloat(layout.rows - 1)
            let verticalPadding = max(0, (size.height - totalHeight) / 2)

            for row in 0..<layout.rows {
                for col in 0..<layout.columns {
                    let index = row * layout.columns + col
                    guard index < viewModel.streams.count else { continue }
                    let x = (slotWidth + spacing) * CGFloat(col)
                    let y = verticalPadding + (slotHeight + spacing) * CGFloat(row)
                    frames[viewModel.streams[index].id] = CGRect(x: x, y: y, width: slotWidth, height: slotHeight)
                }
            }
        }

        return frames
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
        } else {
            // Single stream: any d-pad press shows controls
            showControlsWithFocus()
        }
    }
    #endif

    private func showControlsWithFocus() {
        withAnimation(.easeInOut(duration: 0.25)) {
            viewModel.showControlsTemporarily()
        }
    }

    private func showChannelBadgesTemporarily() {
        // Cancel existing timer
        channelBadgeTimer?.invalidate()

        // Show badges
        withAnimation(.easeInOut(duration: 0.25)) {
            showChannelBadges = true
        }

        // Hide after 5 seconds (only if controls are not showing)
        channelBadgeTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                if !viewModel.showControls {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showChannelBadges = false
                    }
                }
            }
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
        #if os(tvOS)
        .onExitCommand {
            // Menu/Back pressed while controls visible - hide controls
            withAnimation(.easeOut(duration: 0.2)) {
                viewModel.showControls = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusArea = .streamGrid
            }
        }
        #endif
    }

    private var exitConfirmationOverlay: some View {
        let cancelFocused = focusArea == .exitConfirmButton(0)
        let exitFocused = focusArea == .exitConfirmButton(1)

        return ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            // Confirmation dialog
            VStack(spacing: 24) {
                Text("Exit Multiview?")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                Text("You have \(viewModel.streamCount) streams open.")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 32) {
                    // Cancel button - standard glass styling
                    Button {
                        showExitConfirmation = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focusArea = .streamGrid
                        }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 180, height: 58)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(cancelFocused ? .white.opacity(0.18) : .white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(
                                                cancelFocused ? .white.opacity(0.25) : .white.opacity(0.08),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .focused($focusArea, equals: .exitConfirmButton(0))
                    .scaleEffect(cancelFocused ? 1.02 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cancelFocused)

                    // Exit button - destructive styling
                    Button {
                        forceExitPlayer()
                    } label: {
                        Text("Exit")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 180, height: 58)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(exitFocused ? .red.opacity(0.25) : .white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(
                                                exitFocused ? .red.opacity(0.4) : .white.opacity(0.08),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .focused($focusArea, equals: .exitConfirmButton(1))
                    .scaleEffect(exitFocused ? 1.02 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: exitFocused)
                }
                .padding(.top, 16)
            }
            .padding(48)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        #if os(tvOS)
        .onExitCommand {
            // Menu/Back on confirmation = cancel
            showExitConfirmation = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusArea = .streamGrid
            }
        }
        #endif
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
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
    }

    private struct ControlButtonConfig {
        let icon: String
        let label: String
        var isLarge: Bool = false
        let action: () -> Void
    }

    private func buildControlButtons() -> [ControlButtonConfig] {
        var buttons: [ControlButtonConfig] = []

        // Note: Pause/play removed for live TV since time-shifting isn't implemented
        // Live TV streams are real-time only for now

        // Layout controls (only when multiple streams)
        if viewModel.streamCount > 1 {
            if viewModel.isFocusedStreamInSidebar {
                // Focused stream is in sidebar - offer to expand it to main
                buttons.append(ControlButtonConfig(
                    icon: "arrow.up.left.and.arrow.down.right",
                    label: "Expand",
                    action: {
                        viewModel.expandFocusedStream()
                    }
                ))
            } else if viewModel.isFocusLayout {
                // Focused stream is the main one - offer to reset to grid
                buttons.append(ControlButtonConfig(
                    icon: "rectangle.split.2x2",
                    label: "Grid View",
                    action: {
                        viewModel.resetLayout()
                    }
                ))
            } else {
                // Grid layout - offer to enlarge focused stream
                buttons.append(ControlButtonConfig(
                    icon: "rectangle.expand.vertical",
                    label: "Enlarge",
                    action: {
                        if let slotId = viewModel.focusedStream?.id {
                            viewModel.setFocusedLayout(on: slotId)
                        }
                    }
                ))
            }
        }

        // Add Stream button (2nd position)
        if viewModel.canAddStream {
            buttons.append(ControlButtonConfig(
                icon: "plus.circle.fill",
                label: "Add Stream",
                action: {
                    viewModel.replaceSlotIndex = nil  // Adding, not replacing
                    viewModel.showChannelPicker = true
                }
            ))
        }

        // Replace button (replace focused stream with new channel)
        buttons.append(ControlButtonConfig(
            icon: "arrow.triangle.2.circlepath",
            label: "Replace",
            action: {
                viewModel.replaceSlotIndex = viewModel.focusedSlotIndex
                viewModel.showChannelPicker = true
            }
        ))

        // Remove stream button (only when multiple streams)
        if viewModel.streamCount > 1 {
            buttons.append(ControlButtonConfig(
                icon: "minus.circle.fill",
                label: "Remove",
                action: {
                    print("📺 Remove pressed: focusedSlotIndex=\(viewModel.focusedSlotIndex), streamCount=\(viewModel.streamCount)")
                    viewModel.removeStream(at: viewModel.focusedSlotIndex)
                    // If only 1 stream left, hide controls
                    if viewModel.streamCount <= 1 {
                        viewModel.showControls = false
                    }
                }
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
        print("📺 handleExitCommand: showExitConfirmation=\(showExitConfirmation), showChannelPicker=\(viewModel.showChannelPicker), showControls=\(viewModel.showControls), streamCount=\(viewModel.streamCount)")
        if showExitConfirmation {
            // Cancel the confirmation and return to streams
            print("📺 handleExitCommand: Cancelling exit confirmation")
            showExitConfirmation = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusArea = .streamGrid
            }
        } else if viewModel.showChannelPicker {
            print("📺 handleExitCommand: Closing channel picker")
            viewModel.showChannelPicker = false
        } else if viewModel.showControls {
            // Hide controls and return focus to stream grid
            print("📺 handleExitCommand: Hiding controls")
            withAnimation(.easeOut(duration: 0.2)) {
                viewModel.showControls = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusArea = .streamGrid
            }
        } else {
            print("📺 handleExitCommand: Calling dismissPlayer")
            dismissPlayer()
        }
    }
    #endif

    private func dismissPlayer() {
        // Check if we should show confirmation for multiview
        print("📺 dismissPlayer: confirmExitMultiview=\(confirmExitMultiview), streamCount=\(viewModel.streamCount)")
        if confirmExitMultiview && viewModel.streamCount > 1 {
            print("📺 dismissPlayer: Showing exit confirmation")
            showExitConfirmation = true
        } else {
            print("📺 dismissPlayer: Forcing exit (no confirmation needed)")
            forceExitPlayer()
        }
    }

    private func forceExitPlayer() {
        viewModel.stopAllStreams()
        onDismiss()
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
    LiveTVPlayerView(
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
        onDismiss: {}
    )
}
