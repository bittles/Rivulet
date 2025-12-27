//
//  UniversalPlayerView.swift
//  Rivulet
//
//  Universal video player using MPV with HDR passthrough
//

import SwiftUI

struct UniversalPlayerView: View {
    @StateObject private var viewModel: UniversalPlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.focusScopeManager) private var focusScopeManager

    @State private var hasStartedPlayback = false
    @State private var playerController: MPVMetalViewController?

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
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: viewModel.showInfoPanel)
        // Always focusable - we handle all input manually
        .focusable(true)
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
                handleMoveCommand(direction)
            }
        }
        .onPlayPauseCommand {
            if viewModel.showInfoPanel {
                // Play/pause should still work when panel is open
                viewModel.togglePlayPause()
            } else {
                handleSelectCommand()
            }
        }
        .onExitCommand {
            // Handle Menu/Back button - close UI elements before dismissing
            if viewModel.isScrubbing {
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

    // MARK: - Input Handling

    #if os(tvOS)
    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        // Show controls on any input
        viewModel.showControlsTemporarily()

        switch direction {
        case .left:
            // Enter or continue scrubbing - increases speed with each press
            viewModel.scrubInDirection(forward: false)
        case .right:
            // Enter or continue scrubbing - increases speed with each press
            viewModel.scrubInDirection(forward: true)
        case .down:
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
            // Cancel scrubbing on up
            if viewModel.isScrubbing {
                viewModel.cancelScrub()
            }
        @unknown default:
            break
        }
    }

    private func handleSelectCommand() {
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
