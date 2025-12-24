//
//  UniversalPlayerViewModel.swift
//  Rivulet
//
//  ViewModel managing playback state using MPV player
//

import SwiftUI
import Combine

@MainActor
final class UniversalPlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var playbackState: UniversalPlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isBuffering = false
    @Published private(set) var errorMessage: String?

    @Published var showControls = true
    @Published private(set) var audioTracks: [MediaTrack] = []
    @Published private(set) var subtitleTracks: [MediaTrack] = []
    @Published private(set) var currentAudioTrackId: Int?
    @Published private(set) var currentSubtitleTrackId: Int?

    // MARK: - Player Instance

    private(set) var mpvPlayerWrapper: MPVPlayerWrapper

    // MARK: - Metadata

    let metadata: PlexMetadata
    var title: String { metadata.title ?? "Unknown" }
    var subtitle: String? {
        if metadata.type == "episode" {
            let show = metadata.grandparentTitle ?? ""
            let season = metadata.parentIndex.map { "S\($0)" } ?? ""
            let episode = metadata.index.map { "E\($0)" } ?? ""
            return "\(show) \(season)\(episode)"
        }
        return metadata.year.map { String($0) }
    }

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()
    private var controlsTimer: Timer?
    private let controlsHideDelay: TimeInterval = 5

    // MARK: - Playback Context

    let serverURL: String
    let authToken: String
    let startOffset: TimeInterval?

    // MARK: - Stream URL (computed once)

    private(set) var streamURL: URL?
    private(set) var streamHeaders: [String: String] = [:]

    // MARK: - Initialization

    init(
        metadata: PlexMetadata,
        serverURL: String,
        authToken: String,
        startOffset: TimeInterval? = nil
    ) {
        self.metadata = metadata
        self.serverURL = serverURL
        self.authToken = authToken
        self.startOffset = startOffset
        self.mpvPlayerWrapper = MPVPlayerWrapper()

        setupPlayer()
        prepareStreamURL()
    }

    private func setupPlayer() {
        bindPlayerState()
    }

    private func prepareStreamURL() {
        let networkManager = PlexNetworkManager.shared

        guard let ratingKey = metadata.ratingKey else { return }

        // MPV: Use true direct play - stream raw file without any transcoding
        // MPV can handle MKV, HEVC, H264, DTS, TrueHD, ASS/SSA subs natively with HDR passthrough
        if let partKey = metadata.Media?.first?.Part?.first?.key {
            streamURL = networkManager.buildVLCDirectPlayURL(
                serverURL: serverURL,
                authToken: authToken,
                partKey: partKey
            )
        } else {
            // Fallback to direct stream if no part key available
            streamURL = networkManager.buildDirectStreamURL(
                serverURL: serverURL,
                authToken: authToken,
                ratingKey: ratingKey,
                offsetMs: Int((startOffset ?? 0) * 1000)
            )
        }

        streamHeaders = [
            "X-Plex-Token": authToken,
            "X-Plex-Client-Identifier": PlexAPI.clientIdentifier,
            "X-Plex-Platform": PlexAPI.platform,
            "X-Plex-Device": PlexAPI.deviceName,
            "X-Plex-Product": PlexAPI.productName
        ]

        if let url = streamURL {
            print("🎬 MPV Direct Play URL: \(url.absoluteString)")
        }
    }

    private func bindPlayerState() {
        mpvPlayerWrapper.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playbackState = state
                self?.isBuffering = state == .buffering

                // Auto-hide controls when playing
                if state == .playing {
                    self?.startControlsHideTimer()
                } else {
                    self?.controlsTimer?.invalidate()
                }
            }
            .store(in: &cancellables)

        mpvPlayerWrapper.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.currentTime = time
                // Also update duration from wrapper
                if let wrapper = self?.mpvPlayerWrapper, wrapper.duration > 0 {
                    self?.duration = wrapper.duration
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

        do {
            try await mpvPlayerWrapper.load(url: url, headers: streamHeaders, startTime: startOffset)
            mpvPlayerWrapper.play()

            // Update duration after loading
            self.duration = mpvPlayerWrapper.duration

            // Update track lists
            updateTrackLists()

            startControlsHideTimer()
        } catch {
            errorMessage = error.localizedDescription
            playbackState = .failed(.loadFailed(error.localizedDescription))
        }
    }

    /// Called when the MPV view controller is created
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

    func seek(to time: TimeInterval) async {
        await mpvPlayerWrapper.seek(to: time)
        showControlsTemporarily()
    }

    func seekRelative(by seconds: TimeInterval) async {
        await mpvPlayerWrapper.seekRelative(by: seconds)
        showControlsTemporarily()
    }

    // MARK: - Track Selection

    func selectAudioTrack(id: Int) {
        mpvPlayerWrapper.selectAudioTrack(id: id)
        currentAudioTrackId = id
    }

    func selectSubtitleTrack(id: Int?) {
        mpvPlayerWrapper.selectSubtitleTrack(id: id)
        currentSubtitleTrackId = id
    }

    private func updateTrackLists() {
        audioTracks = mpvPlayerWrapper.audioTracks
        subtitleTracks = mpvPlayerWrapper.subtitleTracks
        currentAudioTrackId = mpvPlayerWrapper.currentAudioTrackId
        currentSubtitleTrackId = mpvPlayerWrapper.currentSubtitleTrackId
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

    // MARK: - Cleanup

    deinit {
        controlsTimer?.invalidate()
    }
}
