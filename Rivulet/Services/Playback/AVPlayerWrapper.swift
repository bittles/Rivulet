//
//  AVPlayerWrapper.swift
//  Rivulet
//
//  AVPlayer-based video player for Live TV streams
//  Uses native AVPlayer which is more resource-efficient for multiple simultaneous streams
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class AVPlayerWrapper: NSObject, ObservableObject {

    // MARK: - AVPlayer Components

    @Published private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    // Keep a non-isolated reference for cleanup in deinit
    private nonisolated(unsafe) var _playerForCleanup: AVPlayer?

    // MARK: - State

    private let playbackStateSubject = CurrentValueSubject<UniversalPlaybackState, Never>(.idle)
    private let timeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let errorSubject = PassthroughSubject<PlayerError, Never>()

    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?

    private var _duration: TimeInterval = 0
    private var _isMuted: Bool = false

    // MARK: - Publishers

    var playbackStatePublisher: AnyPublisher<UniversalPlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    var timePublisher: AnyPublisher<TimeInterval, Never> {
        timeSubject.eraseToAnyPublisher()
    }

    var errorPublisher: AnyPublisher<PlayerError, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    // MARK: - Playback State

    var isPlaying: Bool {
        player?.rate ?? 0 > 0
    }

    var currentTime: TimeInterval {
        player?.currentTime().seconds ?? 0
    }

    var duration: TimeInterval {
        _duration
    }

    var isMuted: Bool {
        _isMuted
    }

    // MARK: - Initialization

    override init() {
        super.init()
    }

    deinit {
        // Clean up time observer synchronously in deinit
        // Other observers will be cleaned up by ARC
        if let timeObserver = timeObserver, let player = _playerForCleanup {
            player.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Playback Controls

    func load(url: URL, headers: [String: String]?) async throws {
        print("🎬 AVPlayerWrapper: Loading URL: \(url)")
        playbackStateSubject.send(.loading)

        // Clean up previous player
        cleanupObservers()
        player?.pause()

        // Create asset with headers if needed
        // Note: We don't check isPlayable here because live TS streams from proxies
        // don't support byte-range requests which the check requires
        var options: [String: Any] = [:]
        if let headers = headers, !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }

        let asset = AVURLAsset(url: url, options: options)

        // Create player item directly - let the item status observer handle errors
        playerItem = AVPlayerItem(asset: asset)

        // Configure for live streaming
        playerItem?.preferredForwardBufferDuration = 2  // Buffer 2 seconds ahead
        playerItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = false

        // Create or reuse player
        if player == nil {
            let newPlayer = AVPlayer(playerItem: playerItem)
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            player = newPlayer
            _playerForCleanup = newPlayer
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }

        // Apply mute state
        player?.isMuted = _isMuted

        // Setup observers
        setupObservers()

        print("🎬 AVPlayerWrapper: Starting playback")
        // Start playback for live streams
        player?.play()
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        cleanupObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        _playerForCleanup = nil
        playerItem = nil
        playbackStateSubject.send(.idle)
    }

    func seek(to time: TimeInterval) async {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        await player?.seek(to: cmTime)
        timeSubject.send(time)
    }

    // MARK: - Audio Control

    func setMuted(_ muted: Bool) {
        _isMuted = muted
        player?.isMuted = muted
    }

    // MARK: - Observers

    private func setupObservers() {
        guard let player = player, let playerItem = playerItem else { return }

        // Observe player rate (playing/paused)
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self = self else { return }
                if player.rate > 0 {
                    self.playbackStateSubject.send(.playing)
                } else if self.playbackStateSubject.value == .playing {
                    self.playbackStateSubject.send(.paused)
                }
            }
        }

        // Observe player item status
        itemStatusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    self._duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    // Don't set playing here - let rate observation handle it
                case .failed:
                    let message = item.error?.localizedDescription ?? "Unknown error"
                    self.playbackStateSubject.send(.failed(.unknown(message)))
                    self.errorSubject.send(.unknown(message))
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        // Observe time updates
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.timeSubject.send(time.seconds)
            }
        }

        // Observe buffering
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemPlaybackStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: playerItem
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlayToEnd),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem
        )
    }

    private func cleanupObservers() {
        if let timeObserver = timeObserver, let player = player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        statusObservation?.invalidate()
        statusObservation = nil

        rateObservation?.invalidate()
        rateObservation = nil

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Notifications

    @objc private func playerItemPlaybackStalled() {
        playbackStateSubject.send(.buffering)
    }

    @objc private func playerItemDidPlayToEnd() {
        playbackStateSubject.send(.ended)
    }

    @objc private func playerItemFailedToPlayToEnd(_ notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            playbackStateSubject.send(.failed(.unknown(error.localizedDescription)))
            errorSubject.send(.unknown(error.localizedDescription))
        }
    }

    // MARK: - Lifecycle

    func prepareForReuse() {
        stop()
        _duration = 0
        _isMuted = false
        playbackStateSubject.send(.idle)
        timeSubject.send(0)
    }
}
