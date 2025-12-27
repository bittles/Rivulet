//
//  UniversalPlayerViewModel.swift
//  Rivulet
//
//  ViewModel managing playback state using MPV player
//

import SwiftUI
import Combine
import UIKit

// MARK: - Subtitle Preference

/// Stores user's subtitle preference for auto-selection
struct SubtitlePreference: Codable, Equatable {
    /// Whether subtitles are enabled
    var enabled: Bool
    /// Preferred language code (e.g., "en", "es")
    var languageCode: String?
    /// Preferred codec (e.g., "srt", "ass", "pgs")
    var codec: String?
    /// Whether to prefer hearing impaired tracks
    var preferHearingImpaired: Bool

    static let off = SubtitlePreference(enabled: false, languageCode: nil, codec: nil, preferHearingImpaired: false)

    init(enabled: Bool, languageCode: String?, codec: String?, preferHearingImpaired: Bool) {
        self.enabled = enabled
        self.languageCode = languageCode
        self.codec = codec
        self.preferHearingImpaired = preferHearingImpaired
    }

    /// Create preference from a selected track
    init(from track: MediaTrack) {
        self.enabled = true
        self.languageCode = track.languageCode
        self.codec = track.codec
        self.preferHearingImpaired = track.isHearingImpaired
    }
}

/// Manages subtitle preference persistence
enum SubtitlePreferenceManager {
    private static let key = "subtitlePreference"

    static var current: SubtitlePreference {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let pref = try? JSONDecoder().decode(SubtitlePreference.self, from: data) else {
                return .off
            }
            return pref
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    /// Find best matching subtitle track based on preference
    static func findBestMatch(in tracks: [MediaTrack], preference: SubtitlePreference) -> MediaTrack? {
        guard preference.enabled, let preferredLang = preference.languageCode else {
            return nil
        }

        // Filter tracks by language
        let langMatches = tracks.filter { $0.languageCode == preferredLang }
        guard !langMatches.isEmpty else {
            // No tracks match preferred language - keep subtitles off
            return nil
        }

        // Try to find exact codec match
        if let preferredCodec = preference.codec {
            if let exactMatch = langMatches.first(where: {
                $0.codec == preferredCodec && $0.isHearingImpaired == preference.preferHearingImpaired
            }) {
                return exactMatch
            }
            // Try codec match without hearing impaired preference
            if let codecMatch = langMatches.first(where: { $0.codec == preferredCodec }) {
                return codecMatch
            }
        }

        // Fall back to first track of preferred language with matching HI preference
        if let hiMatch = langMatches.first(where: { $0.isHearingImpaired == preference.preferHearingImpaired }) {
            return hiMatch
        }

        // Fall back to first track of preferred language
        return langMatches.first
    }
}

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

    // MARK: - Playback Settings Panel State (Column-based layout)

    /// Which column is focused: 0 = Subtitles, 1 = Audio (Media Info is not focusable)
    @Published var focusedColumn: Int = 0

    /// Which row within the focused column
    @Published var focusedRowIndex: Int = 0

    /// Number of rows in a given column
    func rowCount(forColumn column: Int) -> Int {
        switch column {
        case 0: return 1 + subtitleTracks.count  // "Off" + subtitle tracks
        case 1: return max(1, audioTracks.count)  // Audio tracks (at least 1)
        default: return 0
        }
    }

    /// Check if a specific setting is focused
    func isSettingFocused(column: Int, index: Int) -> Bool {
        return focusedColumn == column && focusedRowIndex == index
    }

    /// Navigate within settings panel
    func navigateSettings(direction: MoveCommandDirection) {
        switch direction {
        case .up:
            if focusedRowIndex > 0 {
                focusedRowIndex -= 1
            }
        case .down:
            let maxIndex = rowCount(forColumn: focusedColumn) - 1
            if focusedRowIndex < maxIndex {
                focusedRowIndex += 1
            }
        case .left:
            if focusedColumn > 0 {
                focusedColumn -= 1
                // Clamp row index to new column's range
                focusedRowIndex = min(focusedRowIndex, rowCount(forColumn: focusedColumn) - 1)
            }
        case .right:
            if focusedColumn < 1 {  // Only 2 focusable columns (0 and 1)
                focusedColumn += 1
                // Clamp row index to new column's range
                focusedRowIndex = min(focusedRowIndex, rowCount(forColumn: focusedColumn) - 1)
            }
        @unknown default:
            break
        }
    }

    /// Select the currently focused setting
    func selectFocusedSetting() {
        switch focusedColumn {
        case 0:  // Subtitles
            if focusedRowIndex == 0 {
                selectSubtitleTrack(id: nil)
                print("🎬 [SETTINGS] Selected subtitles: Off")
            } else {
                let trackIndex = focusedRowIndex - 1
                if trackIndex < subtitleTracks.count {
                    selectSubtitleTrack(id: subtitleTracks[trackIndex].id)
                    print("🎬 [SETTINGS] Selected subtitle: \(subtitleTracks[trackIndex].name)")
                }
            }
        case 1:  // Audio
            if focusedRowIndex < audioTracks.count {
                selectAudioTrack(id: audioTracks[focusedRowIndex].id)
                print("🎬 [SETTINGS] Selected audio: \(audioTracks[focusedRowIndex].name)")
            }
        default:
            break
        }
    }

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

        // Auto-update tracks when MPV reports them
        mpvPlayerWrapper.tracksPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateTrackLists()
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

    // MARK: - Info Panel Navigation

    /// Reset settings panel state when opening
    func resetSettingsPanel() {
        // Refresh track lists when panel opens
        updateTrackLists()
        focusedColumn = 0
        focusedRowIndex = 0
        print("🎬 [SETTINGS] Opened with \(audioTracks.count) audio, \(subtitleTracks.count) subtitles")
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

        // Save preference
        if let id = id, let track = subtitleTracks.first(where: { $0.id == id }) {
            SubtitlePreferenceManager.current = SubtitlePreference(from: track)
            print("🎬 [SUBTITLE PREF] Saved: \(track.languageCode ?? "?") / \(track.codec ?? "?")")
        } else {
            SubtitlePreferenceManager.current = .off
            print("🎬 [SUBTITLE PREF] Saved: Off")
        }
    }

    /// Whether we've already applied subtitle preference for this playback session
    private var hasAppliedSubtitlePreference = false

    private func updateTrackLists() {
        let previousSubtitleCount = subtitleTracks.count

        audioTracks = mpvPlayerWrapper.audioTracks
        subtitleTracks = mpvPlayerWrapper.subtitleTracks
        currentAudioTrackId = mpvPlayerWrapper.currentAudioTrackId
        currentSubtitleTrackId = mpvPlayerWrapper.currentSubtitleTrackId

        // Apply saved subtitle preference when tracks are first available
        if !hasAppliedSubtitlePreference && !subtitleTracks.isEmpty && previousSubtitleCount == 0 {
            hasAppliedSubtitlePreference = true
            applySubtitlePreference()
        }
    }

    /// Apply saved subtitle preference
    private func applySubtitlePreference() {
        let preference = SubtitlePreferenceManager.current

        if !preference.enabled {
            // User prefers subtitles off
            selectSubtitleTrackWithoutSaving(id: nil)
            print("🎬 [SUBTITLE PREF] Applied: Off (user preference)")
            return
        }

        // Find best matching track
        if let match = SubtitlePreferenceManager.findBestMatch(in: subtitleTracks, preference: preference) {
            selectSubtitleTrackWithoutSaving(id: match.id)
            print("🎬 [SUBTITLE PREF] Applied: \(match.name) (matched \(preference.languageCode ?? "?"))")
        } else {
            // No matching language found - keep subtitles off
            selectSubtitleTrackWithoutSaving(id: nil)
            print("🎬 [SUBTITLE PREF] Applied: Off (no \(preference.languageCode ?? "?") tracks found)")
        }
    }

    /// Select subtitle track without saving preference (for auto-selection)
    private func selectSubtitleTrackWithoutSaving(id: Int?) {
        mpvPlayerWrapper.selectSubtitleTrack(id: id)
        currentSubtitleTrackId = id
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
