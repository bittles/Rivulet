//
//  LiveTVPlayerView.swift
//  Rivulet
//
//  Live TV channel player using MPV
//

import SwiftUI
import Combine

struct LiveTVPlayerView: View {
    let channel: UnifiedChannel
    @StateObject private var viewModel: LiveTVPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var hasStartedPlayback = false
    @State private var playerController: MPVMetalViewController?
    @State private var showMultiView = false

    init(channel: UnifiedChannel) {
        self.channel = channel
        _viewModel = StateObject(wrappedValue: LiveTVPlayerViewModel(channel: channel))
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            // Player Layer
            if let url = viewModel.streamURL {
                MPVPlayerView(
                    url: url,
                    headers: [:],
                    startTime: nil,
                    delegate: viewModel.mpvPlayerWrapper,
                    playerController: $playerController
                )
                .ignoresSafeArea()
            }

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
                LiveTVControlsOverlay(
                    channel: channel,
                    currentProgram: viewModel.currentProgram,
                    isPlaying: viewModel.isPlaying,
                    onPlayPause: { viewModel.togglePlayPause() },
                    onMultiView: {
                        viewModel.stopPlayback()
                        showMultiView = true
                    },
                    onDismiss: { dismiss() }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }
        }
        .fullScreenCover(isPresented: $showMultiView, onDismiss: {
            // When multi-view is dismissed, also dismiss the single player
            dismiss()
        }) {
            MultiStreamPlayerView(initialChannel: channel)
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                if viewModel.showControls {
                    viewModel.showControls = false
                } else {
                    viewModel.showControlsTemporarily()
                }
            }
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            viewModel.togglePlayPause()
            viewModel.showControlsTemporarily()
        }
        .onExitCommand {
            if viewModel.showControls {
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.showControls = false
                }
            } else {
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
            await viewModel.startPlayback()
        }
        .onDisappear {
            viewModel.stopPlayback()
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

            Text(channel.name)
                .font(.headline)
                .foregroundStyle(.white)
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
}

// MARK: - Live TV Player ViewModel

@MainActor
final class LiveTVPlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var playbackState: UniversalPlaybackState = .idle
    @Published private(set) var isBuffering = false
    @Published private(set) var errorMessage: String?
    @Published var showControls = true

    // MARK: - Player

    private(set) var mpvPlayerWrapper: MPVPlayerWrapper
    private(set) var streamURL: URL?

    // MARK: - Channel Info

    let channel: UnifiedChannel
    @Published private(set) var currentProgram: UnifiedProgram?

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var controlsTimer: Timer?
    private let controlsHideDelay: TimeInterval = 5

    // MARK: - Initialization

    init(channel: UnifiedChannel) {
        self.channel = channel
        self.mpvPlayerWrapper = MPVPlayerWrapper()

        // Get stream URL from data store
        self.streamURL = LiveTVDataStore.shared.buildStreamURL(for: channel)

        setupPlayer()
        loadCurrentProgram()
    }

    private func setupPlayer() {
        mpvPlayerWrapper.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playbackState = state
                self?.isBuffering = state == .buffering

                if state == .playing {
                    self?.startControlsHideTimer()
                } else {
                    self?.controlsTimer?.invalidate()
                }
            }
            .store(in: &cancellables)

        mpvPlayerWrapper.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }
            .store(in: &cancellables)
    }

    private func loadCurrentProgram() {
        currentProgram = LiveTVDataStore.shared.getCurrentProgram(for: channel)
    }

    // MARK: - Computed Properties

    var isPlaying: Bool {
        mpvPlayerWrapper.isPlaying
    }

    // MARK: - Playback Controls

    func startPlayback() async {
        guard let url = streamURL else {
            errorMessage = "No stream URL available"
            playbackState = .failed(.invalidURL)
            return
        }

        print("📺 LiveTV: Starting playback of \(channel.name)")
        print("📺 LiveTV: Stream URL: \(url.absoluteString)")

        do {
            // For live streams, no headers needed (M3U URLs are self-contained)
            try await mpvPlayerWrapper.load(url: url, headers: [:], startTime: nil)
            mpvPlayerWrapper.play()
            startControlsHideTimer()
        } catch {
            errorMessage = error.localizedDescription
            playbackState = .failed(.loadFailed(error.localizedDescription))
        }
    }

    func setPlayerController(_ controller: MPVMetalViewController) {
        mpvPlayerWrapper.setPlayerController(controller)
    }

    func stopPlayback() {
        mpvPlayerWrapper.stop()
        controlsTimer?.invalidate()
    }

    func togglePlayPause() {
        if mpvPlayerWrapper.isPlaying {
            mpvPlayerWrapper.pause()
        } else {
            mpvPlayerWrapper.play()
        }
        showControlsTemporarily()
    }

    // MARK: - Controls Visibility

    func showControlsTemporarily() {
        showControls = true
        startControlsHideTimer()
    }

    private func startControlsHideTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: controlsHideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.playbackState == .playing {
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.showControls = false
                    }
                }
            }
        }
    }

    deinit {
        controlsTimer?.invalidate()
    }
}

// MARK: - Live TV Controls Overlay

struct LiveTVControlsOverlay: View {
    let channel: UnifiedChannel
    let currentProgram: UnifiedProgram?
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onMultiView: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Gradient background
            VStack {
                // Top gradient
                LinearGradient(
                    colors: [.black.opacity(0.8), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)

                Spacer()

                // Bottom gradient
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            }
            .ignoresSafeArea()

            VStack {
                // Top bar - channel info
                HStack(alignment: .top) {
                    // Channel logo
                    if let logoURL = channel.logoURL {
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
                            if let number = channel.channelNumber {
                                Text("\(number)")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                            }

                            Text(channel.name)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.white)

                            if channel.isHD {
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

                        if let program = currentProgram {
                            Text(program.title)
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.8))

                            Text(programTimeString(program))
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.top, 50)

                Spacer()

                // Bottom controls
                HStack(spacing: 40) {
                    // Play/Pause button
                    ControlButton(
                        icon: isPlaying ? "pause.fill" : "play.fill",
                        label: isPlaying ? "Pause" : "Play",
                        isLarge: true,
                        action: onPlayPause
                    )

                    // Multi-view button
                    ControlButton(
                        icon: "rectangle.split.2x2",
                        label: "Multi-View",
                        isLarge: false,
                        action: onMultiView
                    )
                }
                .padding(.bottom, 60)
            }
        }
    }

    private var channelIcon: some View {
        Image(systemName: "tv")
            .font(.system(size: 32))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 80, height: 60)
    }

    private func programTimeString(_ program: UnifiedProgram) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let start = formatter.string(from: program.startTime)
        let end = formatter.string(from: program.endTime)
        return "\(start) - \(end)"
    }
}

// MARK: - Control Button

private struct ControlButton: View {
    let icon: String
    let label: String
    var isLarge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: isLarge ? 80 : 64, height: isLarge ? 80 : 64)

                    Image(systemName: icon)
                        .font(.system(size: isLarge ? 36 : 28))
                        .foregroundStyle(.white)
                }

                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
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
