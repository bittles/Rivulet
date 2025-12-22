//
//  PlaybackManager.swift
//  Rivulet
//
//  Manages AVPlayer instance, progress tracking, and Plex reporting
//

import AVFoundation
import AVKit
import Combine

@MainActor
class PlaybackManager: ObservableObject {
    static let shared = PlaybackManager()

    // MARK: - Published State
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isBuffering = false
    @Published private(set) var error: Error?

    // MARK: - Current Item Info
    private(set) var currentItem: PlexMetadata?
    private var ratingKey: String?
    private var serverURL: String?
    private var authToken: String?

    // MARK: - Observers
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var statusObservation: NSKeyValueObservation?
    private var bufferObservation: NSKeyValueObservation?

    // MARK: - Progress Reporting
    private var lastReportedTime: Double = 0
    private let reportingInterval: Double = 10 // Report every 10 seconds
    private let networkManager = PlexNetworkManager.shared

    private init() {}

    // MARK: - Playback Control

    /// Start playing a Plex media item
    func play(
        item: PlexMetadata,
        serverURL: String,
        authToken: String,
        startOffset: Int? = nil
    ) async {
        // Clean up previous playback
        stop()

        self.currentItem = item
        self.ratingKey = item.ratingKey
        self.serverURL = serverURL
        self.authToken = authToken

        // Build the streaming URL
        guard let ratingKey = item.ratingKey else {
            self.error = PlaybackError.invalidURL
            return
        }

        guard let streamURL = await buildStreamURL(
            ratingKey: ratingKey,
            serverURL: serverURL,
            authToken: authToken
        ) else {
            self.error = PlaybackError.invalidURL
            return
        }

        print("PlaybackManager: Starting playback for \(item.title ?? "Unknown")")
        print("PlaybackManager: Stream URL: \(streamURL)")

        // Create player
        let playerItem = AVPlayerItem(url: streamURL)
        let newPlayer = AVPlayer(playerItem: playerItem)

        // Configure for HLS
        newPlayer.automaticallyWaitsToMinimizeStalling = true

        self.player = newPlayer

        // Setup observers
        setupObservers(for: newPlayer)

        // Seek to start offset if resuming
        let offset = startOffset ?? item.viewOffset
        if let offsetMs = offset, offsetMs > 0 {
            let offsetSeconds = Double(offsetMs) / 1000.0
            await seek(to: offsetSeconds)
        }

        // Start playback
        newPlayer.play()
        isPlaying = true

        // Report start to Plex
        await reportProgress(state: .playing)
    }

    /// Pause playback
    func pause() {
        player?.pause()
        isPlaying = false
        Task {
            await reportProgress(state: .paused)
        }
    }

    /// Resume playback
    func resume() {
        player?.play()
        isPlaying = true
        Task {
            await reportProgress(state: .playing)
        }
    }

    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Seek to a specific time in seconds
    func seek(to seconds: Double) async {
        let time = CMTime(seconds: seconds, preferredTimescale: 1)
        await player?.seek(to: time)
        currentTime = seconds
    }

    /// Skip forward by specified seconds
    func skipForward(seconds: Double = 10) async {
        let newTime = min(currentTime + seconds, duration)
        await seek(to: newTime)
    }

    /// Skip backward by specified seconds
    func skipBackward(seconds: Double = 10) async {
        let newTime = max(currentTime - seconds, 0)
        await seek(to: newTime)
    }

    /// Stop playback and clean up
    func stop() {
        // Report stop to Plex
        Task {
            await reportProgress(state: .stopped)
        }

        // Remove observers
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObservation?.invalidate()
        bufferObservation?.invalidate()

        // Stop and clear player
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        // Reset state
        isPlaying = false
        currentTime = 0
        duration = 0
        isBuffering = false
        error = nil
        currentItem = nil
        ratingKey = nil
        lastReportedTime = 0
    }

    // MARK: - Progress

    /// Current progress as a percentage (0.0 - 1.0)
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    /// Formatted current time string
    var currentTimeFormatted: String {
        formatTime(currentTime)
    }

    /// Formatted duration string
    var durationFormatted: String {
        formatTime(duration)
    }

    /// Formatted remaining time string
    var remainingTimeFormatted: String {
        formatTime(duration - currentTime)
    }

    // MARK: - Private Methods

    private func buildStreamURL(
        ratingKey: String,
        serverURL: String,
        authToken: String
    ) async -> URL? {
        // Use the network manager's stream URL builder
        return await networkManager.buildStreamURL(
            serverURL: serverURL,
            authToken: authToken,
            ratingKey: ratingKey
        )
    }

    private func setupObservers(for player: AVPlayer) {
        // Periodic time observer (every 0.5 seconds)
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds

                // Report progress periodically
                if abs(self.currentTime - self.lastReportedTime) >= self.reportingInterval {
                    self.lastReportedTime = self.currentTime
                    await self.reportProgress(state: self.isPlaying ? .playing : .paused)
                }
            }
        }

        // Observe player item status
        statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    let duration = item.duration.seconds
                    if duration.isFinite {
                        self.duration = duration
                    }
                case .failed:
                    self.error = item.error ?? PlaybackError.unknown
                    self.isPlaying = false
                default:
                    break
                }
            }
        }

        // Observe buffering state
        bufferObservation = player.currentItem?.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.isBuffering = item.isPlaybackBufferEmpty
            }
        }
    }

    private func reportProgress(state: PlaybackState) async {
        guard let ratingKey = ratingKey,
              let serverURL = serverURL,
              let authToken = authToken else { return }

        let timeMs = Int(currentTime * 1000)
        let durationMs = Int(duration * 1000)

        do {
            try await networkManager.reportProgress(
                serverURL: serverURL,
                authToken: authToken,
                ratingKey: ratingKey,
                timeMs: timeMs,
                state: state.rawValue,
                duration: durationMs
            )
        } catch {
            print("PlaybackManager: Failed to report progress: \(error)")
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }

        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Playback State

enum PlaybackState: String {
    case playing
    case paused
    case stopped
    case buffering
}

// MARK: - Playback Error

enum PlaybackError: LocalizedError {
    case invalidURL
    case streamNotAvailable
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Unable to create streaming URL"
        case .streamNotAvailable:
            return "Stream is not available"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
