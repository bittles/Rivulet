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
        .focusable()
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
            handleMoveCommand(direction)
        }
        .onPlayPauseCommand {
            // Toggle play/pause and show controls briefly
            viewModel.togglePlayPause()
            viewModel.showControlsTemporarily()
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
        // Show controls on any movement
        viewModel.showControlsTemporarily()

        // Quick seek with left/right when controls hidden
        if !viewModel.showControls {
            switch direction {
            case .left:
                Task { await viewModel.seekRelative(by: -10) }
            case .right:
                Task { await viewModel.seekRelative(by: 10) }
            default:
                break
            }
        }
    }

    private func handleExitCommand() {
        if viewModel.showControls {
            // Hide controls first
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
