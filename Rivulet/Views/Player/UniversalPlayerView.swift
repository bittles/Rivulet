//
//  UniversalPlayerView.swift
//  Rivulet
//
//  Universal video player using MPV with HDR passthrough
//

import SwiftUI

struct UniversalPlayerView: View {
    @StateObject private var viewModel: UniversalPlayerViewModel
    @StateObject private var focusScopeManager = FocusScopeManager()
    @Environment(\.dismiss) private var dismiss

    @State private var hasStartedPlayback = false
    @State private var playerController: MPVMetalViewController?
    @FocusState private var isSkipButtonFocused: Bool

    // Tap vs hold detection for left/right d-pad
    // Since Siri Remote onMoveCommand fires once per click (no begin/end events),
    // we use rapid repeated clicks to detect "hold" behavior
    @State private var lastArrowDirection: MoveCommandDirection?
    @State private var arrowClickCount = 0
    @State private var arrowHoldTimer: Timer?
    private let holdDetectionWindow: TimeInterval = 0.35  // Time window to detect rapid clicks as "hold"

    /// Initialize with metadata (creates viewModel internally)
    init(
        metadata: PlexMetadata,
        serverURL: String,
        authToken: String,
        startOffset: TimeInterval? = nil
    ) {
        _viewModel = StateObject(wrappedValue: UniversalPlayerViewModel(
            metadata: metadata,
            serverURL: serverURL,
            authToken: authToken,
            startOffset: startOffset
        ))
    }

    /// Initialize with an externally-created viewModel (for UIViewController presentation)
    init(viewModel: UniversalPlayerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            // Player Layer
            playerLayer
                .ignoresSafeArea()

            // Loading State
            if viewModel.playbackState == .loading || viewModel.playbackState == .idle {
                loadingView
            }

            // Buffering Indicator
            if viewModel.isBuffering && viewModel.playbackState != .loading {
                bufferingIndicator
            }

            // Error State
            if case .failed(let error) = viewModel.playbackState {
                errorView(message: error.localizedDescription)
            }

            // Skip Button (intro/credits) - shows regardless of controls visibility
            if viewModel.showSkipButton && !viewModel.showInfoPanel {
                skipButtonOverlay
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            // Controls Overlay (transport bar at bottom)
            if viewModel.showControls && viewModel.playbackState.isActive {
                PlayerControlsOverlay(viewModel: viewModel, showInfoPanel: false)
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }

            // Info Panel (independent of controls visibility) - slides from top (triggered by d-pad down)
            if viewModel.showInfoPanel {
                PlayerControlsOverlay(viewModel: viewModel, showInfoPanel: true)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Post-Video Summary Overlay
            if viewModel.postVideoState != .hidden {
                PostVideoSummaryView(viewModel: viewModel, focusScopeManager: focusScopeManager)
                    .zIndex(100)  // Ensure it's above everything
            }
        }
        .environment(\.focusScopeManager, focusScopeManager)
        .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: viewModel.showInfoPanel)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showSkipButton)
        // Focusable when skip button is not focused (let button take focus when visible)
        .focusable(!isSkipButtonFocused)
        .contentShape(Rectangle())
        .onTapGesture {
            // Don't toggle controls if info panel is showing
            guard !viewModel.showInfoPanel else { return }

            // Tap anywhere to show/hide controls
            withAnimation(.easeInOut(duration: 0.25)) {
                if viewModel.showControls {
                    viewModel.showControls = false
                } else {
                    viewModel.showControlsTemporarily()
                }
            }
        }
        #if os(tvOS)
        .onMoveCommand { direction in
            print("🎮 [SwiftUI onMoveCommand] direction: \(direction), showInfoPanel: \(viewModel.showInfoPanel)")
            if viewModel.showInfoPanel {
                // Settings panel navigation - 3 column layout
                switch direction {
                case .up:
                    if viewModel.focusedRowIndex == 0 {
                        // At top row - close panel
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            viewModel.showInfoPanel = false
                        }
                    } else {
                        viewModel.navigateSettings(direction: direction)
                    }
                case .down, .left, .right:
                    viewModel.navigateSettings(direction: direction)
                @unknown default:
                    break
                }
            } else {
                // Left/right are handled by gesture recognizers in PlayerContainerViewController
                // for tap vs hold detection. Only handle up/down here.
                handleMoveCommand(direction)
            }
        }
        .onPlayPauseCommand {
            // Skip button handles its own press via Button action
            guard !isSkipButtonFocused else { return }

            if viewModel.showInfoPanel {
                // Play/pause should still work when panel is open
                viewModel.togglePlayPause()
            } else {
                handleSelectCommand()
            }
        }
        .onExitCommand {
            // Handle Menu/Back button - close UI elements before dismissing
            if viewModel.postVideoState != .hidden {
                // Post-video overlay showing - dismiss it and the player
                viewModel.dismissPostVideo()
                dismiss()
            } else if viewModel.isScrubbing {
                viewModel.cancelScrub()
            } else if viewModel.showInfoPanel {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    viewModel.showInfoPanel = false
                }
            } else if viewModel.showControls {
                withAnimation(.easeOut(duration: 0.25)) {
                    viewModel.showControls = false
                }
            } else {
                // Nothing to close - let the system dismiss the player
                dismiss()
            }
        }
        #endif
        .onChange(of: playerController) { _, controller in
            if let controller = controller {
                viewModel.setPlayerController(controller)
            }
        }
        .task {
            guard !hasStartedPlayback else { return }
            hasStartedPlayback = true
            // Activate player scope when player starts
            focusScopeManager.activate(.player)
            await viewModel.startPlayback()
        }
        .onDisappear {
            viewModel.stopPlayback()
            reportFinalProgress()
            // Deactivate player scope when leaving
            focusScopeManager.deactivate()
        }
        .onChange(of: viewModel.currentTime) { _, newTime in
            // Report progress periodically
            reportProgress(time: newTime)
        }
        // Manage focus scope when settings panel opens/closes
        .onChange(of: viewModel.showInfoPanel) { _, showPanel in
            if showPanel {
                viewModel.resetSettingsPanel()
                focusScopeManager.activate(.playerInfoBar)
            } else {
                focusScopeManager.deactivate()
            }
        }
        // Auto-focus skip button when it appears
        .onChange(of: viewModel.showSkipButton) { _, showButton in
            if showButton && !viewModel.showInfoPanel {
                // Brief delay to ensure button is rendered
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSkipButtonFocused = true
                }
            } else if !showButton {
                isSkipButtonFocused = false
            }
        }
        // Manage focus scope for post-video overlay
        .onChange(of: viewModel.postVideoState) { _, state in
            if state != .hidden {
                focusScopeManager.activate(.postVideo)
            } else {
                focusScopeManager.deactivate()
            }
        }
    }

    // MARK: - Player Layer

    @ViewBuilder
    private var playerLayer: some View {
        if let url = viewModel.streamURL {
            MPVPlayerView(
                url: url,
                headers: viewModel.streamHeaders,
                startTime: viewModel.startOffset,
                delegate: viewModel.mpvPlayerWrapper,
                playerController: $playerController
            )
            .scaleEffect(viewModel.videoFrameState.scale, anchor: .topLeading)
            .offset(viewModel.videoFrameState.offset)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.videoFrameState)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2)
                .tint(.white)

            Text("Loading...")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))

            Text(viewModel.title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Buffering Indicator

    private var bufferingIndicator: some View {
        ProgressView()
            .scaleEffect(1.5)
            .tint(.white)
            .padding(20)
            .background(
                Circle()
                    .fill(.black.opacity(0.5))
            )
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)

            Text("Playback Error")
                .font(.title)
                .foregroundStyle(.white)

            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.top, 20)
        }
    }

    // MARK: - Skip Button Overlay

    private var skipButtonOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    Task { await viewModel.skipActiveMarker() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text(viewModel.skipButtonLabel)
                            .font(.system(size: 24, weight: .semibold))
                    }
                    .foregroundStyle(isSkipButtonFocused ? .white : .white.opacity(0.9))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSkipButtonFocused ? .white.opacity(0.25) : .white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        isSkipButtonFocused ? .white.opacity(0.4) : .white.opacity(0.08),
                                        lineWidth: isSkipButtonFocused ? 2 : 1
                                    )
                            )
                    )
                    .shadow(
                        color: isSkipButtonFocused ? .white.opacity(0.3) : .clear,
                        radius: 12,
                        x: 0,
                        y: 0
                    )
                    .scaleEffect(isSkipButtonFocused ? 1.04 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSkipButtonFocused)
                }
                #if os(tvOS)
                .buttonStyle(CardButtonStyle())
                .focused($isSkipButtonFocused)
                #else
                .buttonStyle(.plain)
                #endif
            }
            .padding(.trailing, 80)
            // Move button up when controls are visible to avoid overlap with transport bar
            .padding(.bottom, viewModel.showControls ? 200 : 80)
            .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        }
    }

    // MARK: - Input Handling

    #if os(tvOS)
    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        print("🎮 [handleMoveCommand] direction: \(direction), isScrubbing: \(viewModel.isScrubbing), infoPanel: \(viewModel.showInfoPanel)")
        switch direction {
        case .left:
            handleArrowInput(forward: false)
        case .right:
            handleArrowInput(forward: true)
        case .down:
            if isSkipButtonFocused {
                // Down from skip button: unfocus skip button, show controls
                isSkipButtonFocused = false
                viewModel.showControlsTemporarily()
                return
            }
            // Show info panel (cancels any active scrubbing)
            if viewModel.isScrubbing {
                viewModel.cancelScrub()
            }
            if !viewModel.showInfoPanel {
                viewModel.resetSettingsPanel()
                withAnimation(.easeOut(duration: 0.3)) {
                    viewModel.showInfoPanel = true
                }
            }
        case .up:
            // If skip button is visible and controls are showing, focus skip button
            if viewModel.showSkipButton && viewModel.showControls && !isSkipButtonFocused {
                isSkipButtonFocused = true
                return
            }
            // Cancel scrubbing on up
            if viewModel.isScrubbing {
                viewModel.cancelScrub()
            }
        @unknown default:
            break
        }
    }

    /// Handle left/right arrow input with tap vs hold detection.
    /// Since Siri Remote doesn't provide press duration, we detect "hold" by rapid repeated clicks.
    /// - First click: Wait briefly, then execute 10s skip if no follow-up
    /// - Rapid clicks (within holdDetectionWindow): Start/continue scrubbing
    private func handleArrowInput(forward: Bool) {
        let currentDirection: MoveCommandDirection = forward ? .right : .left

        // If already scrubbing, each arrow press changes direction or increases speed
        if viewModel.isScrubbing {
            print("🎮 [ARROW] Already scrubbing, adjusting direction/speed")
            viewModel.scrubInDirection(forward: forward)
            viewModel.showControlsTemporarily()
            return
        }

        // Check if this is a rapid follow-up click (same direction within window)
        if lastArrowDirection == currentDirection {
            arrowClickCount += 1
            print("🎮 [ARROW] Rapid click #\(arrowClickCount) detected")

            // Cancel the pending tap action
            arrowHoldTimer?.invalidate()

            if arrowClickCount >= 2 {
                // Multiple rapid clicks = user wants to scrub
                print("🎮 [ARROW] Hold detected via rapid clicks - starting scrub")
                viewModel.scrubInDirection(forward: forward)
                viewModel.showControlsTemporarily()
                // Reset for next interaction
                arrowClickCount = 0
                lastArrowDirection = nil
                return
            }
        } else {
            // Different direction or first click - reset tracking
            arrowClickCount = 1
            lastArrowDirection = currentDirection
        }

        // Cancel any existing timer
        arrowHoldTimer?.invalidate()

        // Start timer - if no follow-up click within window, execute tap action (10s skip)
        arrowHoldTimer = Timer.scheduledTimer(withTimeInterval: holdDetectionWindow, repeats: false) { [self] _ in
            print("🎮 [ARROW] Tap confirmed - skipping \(forward ? "forward" : "backward") 10s")
            Task { @MainActor in
                await viewModel.seekRelative(by: forward ? 10 : -10)
                viewModel.showControlsTemporarily()
            }
            // Reset tracking
            arrowClickCount = 0
            lastArrowDirection = nil
        }
    }

    private func handleSelectCommand() {
        if isSkipButtonFocused {
            // Skip button is focused - trigger skip
            Task { await viewModel.skipActiveMarker() }
            return
        }
        if viewModel.isScrubbing {
            // Commit scrub position
            Task { await viewModel.commitScrub() }
        } else {
            // Normal play/pause toggle
            viewModel.togglePlayPause()
        }
        viewModel.showControlsTemporarily()
    }
    #endif

    // MARK: - Progress Reporting

    private var lastReportedTime: TimeInterval = 0
    private let reportingInterval: TimeInterval = 10

    private func reportProgress(time: TimeInterval) {
        // Report every 10 seconds
        guard abs(time - lastReportedTime) >= reportingInterval else { return }

        Task {
            await PlexProgressReporter.shared.reportProgress(
                ratingKey: viewModel.metadata.ratingKey ?? "",
                time: time,
                duration: viewModel.duration,
                state: viewModel.isPlaying ? "playing" : "paused"
            )
        }
    }

    private func reportFinalProgress() {
        Task {
            await PlexProgressReporter.shared.reportProgress(
                ratingKey: viewModel.metadata.ratingKey ?? "",
                time: viewModel.currentTime,
                duration: viewModel.duration,
                state: "stopped"
            )

            // Mark as watched if > 90% complete
            if viewModel.duration > 0 && viewModel.currentTime / viewModel.duration > 0.9 {
                await PlexProgressReporter.shared.markAsWatched(
                    ratingKey: viewModel.metadata.ratingKey ?? ""
                )
            }
        }
    }
}

// MARK: - Convenience Initializer

extension UniversalPlayerView {
    /// Creates a player view using the shared auth manager for credentials
    init(metadata: PlexMetadata, startOffset: TimeInterval? = nil) {
        let authManager = PlexAuthManager.shared
        self.init(
            metadata: metadata,
            serverURL: authManager.selectedServerURL ?? "",
            authToken: authManager.authToken ?? "",
            startOffset: startOffset
        )
    }
}

#Preview {
    UniversalPlayerView(
        metadata: PlexMetadata(
            ratingKey: "123",
            type: "movie",
            title: "Sample Movie",
            year: 2024,
            duration: 7200000
        ),
        serverURL: "http://localhost:32400",
        authToken: "test-token"
    )
}
