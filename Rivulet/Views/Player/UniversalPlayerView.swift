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

    @State private var hasStartedPlayback = false
    @State private var playerController: MPVMetalViewController?

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

            // Controls Overlay
            if viewModel.showControls && viewModel.playbackState.isActive {
                PlayerControlsOverlay(viewModel: viewModel)
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        // Only capture focus/commands when info panel is NOT showing
        // This allows the info panel buttons to receive focus
        .focusable(!viewModel.showInfoPanel)
        .contentShape(Rectangle())
        .onTapGesture {
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
            // Don't intercept when info panel is showing - let buttons handle focus
            guard !viewModel.showInfoPanel else { return }
            handleMoveCommand(direction)
        }
        .onPlayPauseCommand {
            handleSelectCommand()
        }
        .onExitCommand {
            handleExitCommand()
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
            await viewModel.startPlayback()
        }
        .onDisappear {
            viewModel.stopPlayback()
            reportFinalProgress()
        }
        .onChange(of: viewModel.currentTime) { _, newTime in
            // Report progress periodically
            reportProgress(time: newTime)
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
            if viewModel.showInfoPanel {
                // When info panel is showing, let focus system handle it
                return
            }
            // Enter or continue scrubbing - increases speed with each press
            viewModel.scrubInDirection(forward: false)
        case .right:
            if viewModel.showInfoPanel {
                // When info panel is showing, let focus system handle it
                return
            }
            // Enter or continue scrubbing - increases speed with each press
            viewModel.scrubInDirection(forward: true)
        case .down:
            // Show info panel (cancels any active scrubbing)
            if viewModel.isScrubbing {
                viewModel.cancelScrub()
            }
            if !viewModel.showInfoPanel {
                withAnimation(.easeOut(duration: 0.3)) {
                    viewModel.showInfoPanel = true
                }
            }
        case .up:
            // Hide info panel
            if viewModel.showInfoPanel {
                withAnimation(.easeOut(duration: 0.3)) {
                    viewModel.showInfoPanel = false
                }
            } else if viewModel.isScrubbing {
                // Cancel scrubbing on up if not in info panel
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

    private func handleExitCommand() {
        if viewModel.isScrubbing {
            // Cancel scrubbing first
            viewModel.cancelScrub()
        } else if viewModel.showInfoPanel {
            // Close info panel
            withAnimation(.easeOut(duration: 0.3)) {
                viewModel.showInfoPanel = false
            }
        } else if viewModel.showControls {
            // Hide controls next
            withAnimation(.easeOut(duration: 0.2)) {
                viewModel.showControls = false
            }
        } else {
            // Then dismiss player
            dismiss()
        }
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
