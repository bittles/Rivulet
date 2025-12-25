//
//  UniversalPlayerViewModel.swift
//  Rivulet
//
//  ViewModel managing playback state using MPV player
//

import SwiftUI
import Combine
import UIKit

@MainActor
final class UniversalPlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var playbackState: UniversalPlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isBuffering = false
    @Published private(set) var errorMessage: String?

    @Published var showControls = true
    @Published var showInfoPanel = false
    @Published var isScrubbing = false
    @Published var scrubTime: TimeInterval = 0
    @Published var scrubThumbnail: UIImage?
    @Published private(set) var scrubSpeed: Int = 0  // -6 to 6, 0 = not scrubbing
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
    private var scrubTimer: Timer?
    private let scrubUpdateInterval: TimeInterval = 0.1  // 100ms updates for smooth scrubbing

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

            // TODO: Re-enable after fixing - may cause Metal crash in simulator
            // Preload thumbnails for scrubbing
            // preloadThumbnails()

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

    // MARK: - Scrubbing

    /// Speed multipliers for each level (seconds per 100ms tick)
    private static let scrubSpeeds: [Int: TimeInterval] = [
        1: 1.0,    // 1x = 10 seconds per second
        2: 2.0,    // 2x = 20 seconds per second
        3: 4.0,    // 3x = 40 seconds per second
        4: 8.0,    // 4x = 80 seconds per second
        5: 15.0,   // 5x = 150 seconds per second
        6: 30.0    // 6x = 300 seconds per second (5 min/sec)
    ]

    /// Start or increase scrub speed in given direction
    /// - Parameter forward: true for forward, false for backward
    func scrubInDirection(forward: Bool) {
        let direction = forward ? 1 : -1

        if !isScrubbing {
            // Start scrubbing
            isScrubbing = true
            scrubTime = currentTime
            scrubSpeed = direction  // Start at 1x
            controlsTimer?.invalidate()
            startScrubTimer()
            loadThumbnail(for: scrubTime)
        } else if (scrubSpeed > 0) == forward {
            // Same direction - increase speed up to 6x
            let newSpeed = min(6, abs(scrubSpeed) + 1) * direction
            scrubSpeed = newSpeed
        } else {
            // Opposite direction - decelerate first, then reverse
            if abs(scrubSpeed) > 1 {
                // Slow down by 1 level, keep same direction
                let currentDirection = scrubSpeed > 0 ? 1 : -1
                scrubSpeed = (abs(scrubSpeed) - 1) * currentDirection
            } else {
                // At 1x, switch to opposite direction at 1x
                scrubSpeed = direction
            }
        }

        // Immediate jump on each press
        let jumpAmount: TimeInterval = forward ? 10 : -10
        scrubTime = max(0, min(duration, scrubTime + jumpAmount))
        loadThumbnail(for: scrubTime)
    }

    func startScrubbing() {
        isScrubbing = true
        scrubTime = currentTime
        scrubSpeed = 0
        controlsTimer?.invalidate()
        loadThumbnail(for: scrubTime)
    }

    func updateScrubPosition(_ time: TimeInterval) {
        scrubTime = max(0, min(duration, time))
        loadThumbnail(for: scrubTime)
    }

    func scrubRelative(by seconds: TimeInterval) {
        if !isScrubbing {
            startScrubbing()
        }
        scrubTime = max(0, min(duration, scrubTime + seconds))
        loadThumbnail(for: scrubTime)
    }

    func commitScrub() async {
        stopScrubTimer()
        if isScrubbing {
            await seek(to: scrubTime)
            isScrubbing = false
            scrubSpeed = 0
            scrubThumbnail = nil
        }
    }

    func cancelScrub() {
        stopScrubTimer()
        isScrubbing = false
        scrubSpeed = 0
        scrubTime = currentTime
        scrubThumbnail = nil
        startControlsHideTimer()
    }

    private func startScrubTimer() {
        scrubTimer?.invalidate()
        scrubTimer = Timer.scheduledTimer(withTimeInterval: scrubUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateScrubFromTimer()
            }
        }
    }

    private func stopScrubTimer() {
        scrubTimer?.invalidate()
        scrubTimer = nil
    }

    private func updateScrubFromTimer() {
        guard isScrubbing, scrubSpeed != 0 else { return }

        let speedMagnitude = abs(scrubSpeed)
        let direction: TimeInterval = scrubSpeed > 0 ? 1 : -1
        let secondsPerTick = Self.scrubSpeeds[speedMagnitude] ?? 1.0

        let newTime = scrubTime + (secondsPerTick * direction)
        scrubTime = max(0, min(duration, newTime))

        // Stop at boundaries
        if scrubTime <= 0 || scrubTime >= duration {
            scrubSpeed = 0
            stopScrubTimer()
        }

        loadThumbnail(for: scrubTime)
    }

    private func loadThumbnail(for time: TimeInterval) {
        // TODO: Thumbnail loading disabled - causes Metal crash in simulator
        // The URLSession with custom SSL delegate appears to interfere with
        // MoltenVK's Metal command buffer lifecycle
        return

        /*
        guard let partId = metadata.Media?.first?.Part?.first?.id else {
            print("⚠️ No part ID available for thumbnails")
            return
        }

        Task {
            let thumbnail = await PlexThumbnailService.shared.getThumbnail(
                partId: partId,
                time: time,
                serverURL: serverURL,
                authToken: authToken
            )
            await MainActor.run {
                self.scrubThumbnail = thumbnail
            }
        }
        */
    }

    /// Preload thumbnails when playback starts
    func preloadThumbnails() {
        guard let partId = metadata.Media?.first?.Part?.first?.id else {
            print("⚠️ No part ID available for thumbnail preload")
            return
        }
        print("🖼️ Preloading BIF thumbnails for part \(partId)")
        PlexThumbnailService.shared.preloadBIF(
            partId: partId,
            serverURL: serverURL,
            authToken: authToken
        )
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
        scrubTimer?.invalidate()
    }
}
