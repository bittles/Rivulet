//
//  UniversalPlayerView.swift
//  Rivulet
//
//  Universal video player using MPV with HDR passthrough
//

import SwiftUI
import Combine
#if os(tvOS)
import GameController
#endif

// MARK: - Hold Detection Helper

/// Detects tap vs hold for left/right navigation on tvOS remote using GameController framework.
/// Only responds to physical clicks (buttonA), not capacitive touches on the touchpad.
@MainActor
final class RemoteHoldDetector: ObservableObject {
    private var pressStartTime: Date?
    private var pressDirection: Bool?  // true = right, false = left
    private var holdTimer: Timer?
    private(set) var isHolding = false
    private(set) var isScrubbing = false  // True once scrubbing starts, until reset
    var isEnabled = true  // Set to false to let SwiftUI handle focus navigation

    private let holdThreshold: TimeInterval = 0.4  // How long before it becomes a hold

    var onTap: ((Bool) -> Void)?  // forward: Bool
    var onHoldStart: ((Bool) -> Void)?  // forward: Bool (called once when hold detected)
    var onSpeedTap: ((Bool) -> Void)?  // forward: Bool (called for taps while scrubbing)

    #if os(tvOS)
    private var controllerObserver: NSObjectProtocol?

    /// Current dpad position (capacitive touch) - used to determine direction when clicking
    private var currentDpadX: Float = 0
    /// Last significant direction detected (persists until finger is lifted from touchpad)
    private var lastSignificantDirection: Bool? = nil  // true = right, false = left, nil = center

    func startMonitoring() {
        print("🎮 [GC] Starting GameController monitoring")

        // Set up existing controllers
        for controller in GCController.controllers() {
            setupController(controller)
        }

        // Watch for new controllers
        controllerObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let controller = notification.object as? GCController {
                self?.setupController(controller)
            }
        }
    }

    func stopMonitoring() {
        print("🎮 [GC] Stopping GameController monitoring")
        clearControllerHandlers()
        if let observer = controllerObserver {
            NotificationCenter.default.removeObserver(observer)
            controllerObserver = nil
        }
        holdTimer?.invalidate()
    }

    func pauseMonitoring() {
        print("🎮 [GC] Pausing GameController monitoring")
        clearControllerHandlers()
        isEnabled = false
    }

    func resumeMonitoring() {
        print("🎮 [GC] Resuming GameController monitoring")
        for controller in GCController.controllers() {
            setupController(controller)
        }
        isEnabled = true
    }

    private func clearControllerHandlers() {
        for controller in GCController.controllers() {
            controller.microGamepad?.dpad.valueChangedHandler = nil
            controller.microGamepad?.buttonA.pressedChangedHandler = nil
            controller.extendedGamepad?.dpad.valueChangedHandler = nil
        }
    }

    private func setupController(_ controller: GCController) {
        print("🎮 [GC] Setting up controller: \(controller.vendorName ?? "Unknown")")

        // Use microGamepad for Siri Remote
        if let micro = controller.microGamepad {
            micro.reportsAbsoluteDpadValues = true

            // Track dpad position (capacitive touch) - this tells us WHERE the finger is
            micro.dpad.valueChangedHandler = { [weak self] (dpad, xValue, yValue) in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.currentDpadX = xValue

                    // Track last significant direction (for click detection)
                    // Direction persists until finger is clearly lifted (centered position)
                    let threshold: Float = 0.3
                    if xValue > threshold {
                        self.lastSignificantDirection = true  // right
                    } else if xValue < -threshold {
                        self.lastSignificantDirection = false  // left
                    } else if abs(xValue) < 0.15 && abs(yValue) < 0.15 {
                        // Only clear when truly at rest position (finger lifted)
                        self.lastSignificantDirection = nil
                        // Note: Scrubbing continues until select/play is pressed or up/down cancels
                    }
                    // Values between 0.15 and threshold are ambiguous - keep previous direction
                }
            }

            // buttonA is the physical click on the touchpad - this is what we respond to
            micro.buttonA.pressedChangedHandler = { [weak self] (button, value, pressed) in
                Task { @MainActor [weak self] in
                    self?.handleButtonA(pressed: pressed)
                }
            }
            print("🎮 [GC] MicroGamepad handlers set (dpad for direction, buttonA for click)")
        }

        // Also try extendedGamepad for other controllers (game controllers, etc.)
        if let extended = controller.extendedGamepad {
            extended.dpad.valueChangedHandler = { [weak self] (dpad, xValue, yValue) in
                Task { @MainActor [weak self] in
                    self?.handleExtendedDpad(x: xValue, y: yValue)
                }
            }
            print("🎮 [GC] ExtendedGamepad D-pad handler set")
        }
    }

    /// Handle physical click on the Siri Remote touchpad
    private func handleButtonA(pressed: Bool) {
        // When disabled, let SwiftUI handle all input (e.g., for post-video focus navigation)
        guard isEnabled else { return }

        let threshold: Float = 0.3  // How far left/right counts as directional

        if pressed {
            // Button pressed - check if it's a directional click
            // First check current position, then fall back to last known direction
            // (handles case where dpad briefly reports center during the physical click action)
            if currentDpadX > threshold {
                handleDirectionPressed(forward: true)
            } else if currentDpadX < -threshold {
                handleDirectionPressed(forward: false)
            } else if let direction = lastSignificantDirection {
                // Use last known direction - it persists until finger is lifted
                handleDirectionPressed(forward: direction)
            }
            // Center click with finger lifted - not a directional action
        } else {
            // Button released
            handleDirectionReleased()
        }
    }

    /// Handle extended gamepad dpad (for game controllers that have physical dpad buttons)
    private func handleExtendedDpad(x: Float, y: Float) {
        guard isEnabled else { return }

        let threshold: Float = 0.5

        if x > threshold {
            handleDirectionPressed(forward: true)
        } else if x < -threshold {
            handleDirectionPressed(forward: false)
        } else {
            handleDirectionReleased()
        }
    }

    private func handleDirectionPressed(forward: Bool) {
        // If already pressing in same direction, ignore
        if pressDirection == forward { return }

        // If pressing opposite direction, treat as release first
        if pressDirection != nil {
            handleDirectionReleased()
        }

        // If already scrubbing, taps immediately increase speed (no hold detection needed)
        if isScrubbing {
            print("🎮 [GC] Speed tap while scrubbing: \(forward ? "RIGHT" : "LEFT")")
            pressDirection = forward
            onSpeedTap?(forward)
            return
        }

        print("🎮 [GC] Direction CLICKED: \(forward ? "RIGHT" : "LEFT")")
        pressStartTime = Date()
        pressDirection = forward
        isHolding = false

        // Start hold timer - after threshold, it becomes a hold (starts scrubbing at 1x)
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.pressDirection != nil else { return }
                self.isHolding = true
                self.isScrubbing = true
                print("🎮 [GC] Hold detected - starting scrub \(forward ? "forward" : "backward") at 1x")
                self.onHoldStart?(forward)
            }
        }
    }

    private func handleDirectionReleased() {
        guard let forward = pressDirection else { return }

        print("🎮 [GC] Click released, wasHolding: \(isHolding), isScrubbing: \(isScrubbing)")
        holdTimer?.invalidate()
        holdTimer = nil

        if isHolding || isScrubbing {
            // Was a hold or speed tap - scrubbing remains active
            print("🎮 [GC] Scrubbing active at current speed")
        } else {
            // Was a tap (not scrubbing)
            print("🎮 [GC] Tap detected - seeking \(forward ? "+10s" : "-10s")")
            onTap?(forward)
        }

        pressStartTime = nil
        pressDirection = nil
        isHolding = false  // Reset for next press, but keep isScrubbing
    }
    #endif

    func reset() {
        #if os(tvOS)
        holdTimer?.invalidate()
        holdTimer = nil
        #endif
        pressStartTime = nil
        pressDirection = nil
        isHolding = false
        isScrubbing = false
    }
}

struct UniversalPlayerView: View {
    @StateObject private var viewModel: UniversalPlayerViewModel
    @StateObject private var focusScopeManager = FocusScopeManager()
    @StateObject private var holdDetector = RemoteHoldDetector()
    @Environment(\.dismiss) private var dismiss

    @State private var hasStartedPlayback = false
    @State private var playerController: MPVMetalViewController?
    @State private var lastReportedTime: TimeInterval = 0
    @FocusState private var isSkipButtonFocused: Bool

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
            // Player content layer - handles input when post-video is hidden
            playerContentLayer
                .zIndex(0)

            // Post-Video Summary Overlay - separate layer with its own focus handling
            if viewModel.postVideoState != .hidden {
                PostVideoSummaryView(viewModel: viewModel, focusScopeManager: focusScopeManager)
                    .zIndex(100)  // Ensure it's above everything
            }
        }
        .environment(\.focusScopeManager, focusScopeManager)
        .animation(.easeInOut(duration: 1.0), value: viewModel.playbackState)
        .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: viewModel.showInfoPanel)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showSkipButton)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: viewModel.seekIndicator)
        .animation(.easeInOut(duration: 0.5), value: viewModel.showPausedPoster)
        #if os(tvOS)
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
        // Note: Menu/Back button handling is done in PlayerContainerViewController
        // to intercept the event before SwiftUI can dismiss the player.
        // Do NOT add onExitCommand here - it would fire after PlayerContainerViewController
        // has already processed the event, causing double-handling.
        #endif
        .onChange(of: playerController) { _, controller in
            if let controller = controller {
                viewModel.setPlayerController(controller)
            }
        }
        .onAppear {
            #if os(tvOS)
            // Configure hold detector callbacks for tap vs hold on left/right
            holdDetector.onTap = { [weak viewModel] forward in
                guard let vm = viewModel, !vm.showInfoPanel, vm.postVideoState == .hidden else { return }
                Task { await vm.seekRelative(by: forward ? 10 : -10) }
                vm.showControlsTemporarily()
            }
            holdDetector.onHoldStart = { [weak viewModel] forward in
                guard let vm = viewModel, !vm.showInfoPanel, vm.postVideoState == .hidden else { return }
                // Start scrubbing at 1x - additional taps will increase speed
                vm.scrubInDirection(forward: forward)
                vm.showControlsTemporarily()
            }
            holdDetector.onSpeedTap = { [weak viewModel] forward in
                guard let vm = viewModel, !vm.showInfoPanel, vm.postVideoState == .hidden else { return }
                // Increase scrub speed (or change direction if tapping opposite way)
                vm.scrubInDirection(forward: forward)
                vm.showControlsTemporarily()
            }
            // Start GameController monitoring for D-pad
            holdDetector.startMonitoring()
            #endif
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
            #if os(tvOS)
            holdDetector.stopMonitoring()
            #endif
            holdDetector.reset()
            // Deactivate player scope when leaving
            focusScopeManager.deactivate()
            // Notify that Plex data should be refreshed (watch progress may have changed)
            // Delay slightly to let Plex server process the progress update before we request fresh hubs
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(name: .plexDataNeedsRefresh, object: nil)
            }
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
                #if os(tvOS)
                // Pause GameController monitoring so SwiftUI can handle focus navigation
                holdDetector.pauseMonitoring()
                #endif
            } else {
                focusScopeManager.deactivate()
                #if os(tvOS)
                holdDetector.resumeMonitoring()
                #endif
            }
        }
    }

    // MARK: - Player Content Layer (all player UI except post-video)

    @ViewBuilder
    private var playerContentLayer: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            // Player Layer
            playerLayer
                .ignoresSafeArea()

            // Loading State or Paused Poster (shows after 5s pause)
            if viewModel.playbackState == .loading || viewModel.playbackState == .idle || viewModel.showPausedPoster {
                loadingView
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.easeIn(duration: 1.0)),
                            removal: .opacity.animation(.easeOut(duration: 0.5))
                        )
                    )
            }

            // Buffering Indicator
            if viewModel.isBuffering && viewModel.playbackState != .loading {
                bufferingIndicator
            }

            // Seek Indicator (10s skip)
            if let indicator = viewModel.seekIndicator {
                seekIndicatorView(indicator)
                    .transition(.scale.combined(with: .opacity))
            }

            // Error State
            if case .failed(let error) = viewModel.playbackState {
                errorView(message: error.localizedDescription)
            }

            // Skip Button (intro/credits) - shows regardless of controls visibility, but not during post-video
            if viewModel.showSkipButton && !viewModel.showInfoPanel && viewModel.postVideoState == .hidden {
                skipButtonOverlay
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            // Controls Overlay (transport bar at bottom)
            // Always show when scrubbing so user can see the progress bar, but not during post-video
            if (viewModel.showControls || viewModel.isScrubbing) && viewModel.playbackState.isActive && viewModel.postVideoState == .hidden {
                PlayerControlsOverlay(viewModel: viewModel, showInfoPanel: false)
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }

            // Info Panel (independent of controls visibility) - slides from top (triggered by d-pad down)
            if viewModel.showInfoPanel {
                VStack {
                    PlayerControlsOverlay(viewModel: viewModel, showInfoPanel: true)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)  // Keep above other elements during animation
            }
        }
        // Focusable when skip button is not focused and post-video is not showing
        .focusable(!isSkipButtonFocused && viewModel.postVideoState == .hidden)
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
            // When post-video is showing, don't handle - let SwiftUI manage button focus
            guard viewModel.postVideoState == .hidden else { return }

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
                // Left/right are handled by GameController via RemoteHoldDetector
                // for tap vs hold detection. Only handle up/down here.
                handleMoveCommand(direction)
            }
        }
        #endif
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
        ZStack {
            // Solid black background (fallback)
            Color.black
                .ignoresSafeArea()

            // Background art (passed from detail view - instant display)
            if let artImage = viewModel.loadingArtImage {
                Image(uiImage: artImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            }

            // Gradient overlay for readability
            LinearGradient(
                colors: [
                    .black.opacity(0.9),
                    .black.opacity(0.6),
                    .black.opacity(0.4),
                    .black.opacity(0.6)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()

            // Content
            HStack(alignment: .center, spacing: 0) {
                // Left side - metadata
                VStack(alignment: .leading, spacing: 16) {
                    // Show title (for episodes)
                    if let grandparentTitle = viewModel.metadata.grandparentTitle {
                        Text(grandparentTitle)
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    // Main title
                    Text(viewModel.title)
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    // Season/Episode info
                    if let seasonNum = viewModel.metadata.parentIndex,
                       let episodeNum = viewModel.metadata.index {
                        Text("Season \(seasonNum), Episode \(episodeNum)")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    // Year and duration
                    HStack(spacing: 16) {
                        if let year = viewModel.metadata.year {
                            Text(String(year))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        if let duration = viewModel.metadata.duration {
                            Text(formatDuration(duration))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        if let rating = viewModel.metadata.contentRating {
                            Text(rating)
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .font(.body)

                    Spacer()

                    // Loading indicator (only show when actually loading, not when paused)
                    if !viewModel.showPausedPoster {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Loading...")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.leading, 80)
                .padding(.vertical, 60)

                Spacer()

                // Right side - poster (passed from detail view - instant display)
                if let thumbImage = viewModel.loadingThumbImage {
                    Image(uiImage: thumbImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)
                        .padding(.trailing, 80)
                }
            }
        }
    }

    private func formatDuration(_ milliseconds: Int) -> String {
        let totalMinutes = milliseconds / 60000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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

    // MARK: - Seek Indicator View

    private func seekIndicatorView(_ indicator: SeekIndicator) -> some View {
        Image(systemName: indicator.systemImage)
            .font(.system(size: 48, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 88, height: 88)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.black.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
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
        // Hide paused poster on any d-pad input
        viewModel.hidePausedPoster()

        switch direction {
        case .left, .right:
            // Left/right are handled by GameController via RemoteHoldDetector
            // which gives us actual press/release timing for tap vs hold detection.
            // We ignore onMoveCommand for these directions.
            break
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
                holdDetector.reset()
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
                holdDetector.reset()
            }
        @unknown default:
            break
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
            holdDetector.reset()
        } else {
            // Normal play/pause toggle
            viewModel.togglePlayPause()
        }
        viewModel.showControlsTemporarily()
    }
    #endif

    // MARK: - Progress Reporting

    private let reportingInterval: TimeInterval = 10

    private func reportProgress(time: TimeInterval) {
        // Report every 10 seconds
        guard abs(time - lastReportedTime) >= reportingInterval else { return }
        lastReportedTime = time

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
