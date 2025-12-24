//
//  MPVMetalViewController.swift
//  Rivulet
//
//  MPV player view controller with Metal rendering and HDR support
//

import Foundation
import UIKit
import Libmpv

final class MPVMetalViewController: UIViewController {

    // MARK: - Properties

    private var metalLayer = MetalLayer()
    private var mpv: OpaquePointer?
    private lazy var queue = DispatchQueue(label: "mpv", qos: .userInitiated)

    weak var delegate: MPVPlayerDelegate?
    var playUrl: URL?
    var httpHeaders: [String: String]?
    var startTime: Double?

    private var timeObserverActive = false
    private var currentState: MPVPlayerState = .idle
    private var isShuttingDown = false

    // MARK: - Simulator Detection

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - HDR Support

    var hdrAvailable: Bool {
        let maxEDRRange = view.window?.screen.potentialEDRHeadroom ?? 1.0
        let sigPeak = getDouble(MPVProperty.videoParamsSigPeak)
        return maxEDRRange > 1.0 && sigPeak > 1.0
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        metalLayer.frame = view.frame
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor

        view.layer.addSublayer(metalLayer)

        setupMpv()

        if let url = playUrl {
            loadFile(url)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalLayer.frame = view.frame
    }

    deinit {
        shutdownMpv()
    }

    private func shutdownMpv() {
        guard mpv != nil, !isShuttingDown else { return }
        isShuttingDown = true

        // Clear delegate to prevent callbacks during shutdown
        delegate = nil

        // Clear the wakeup callback to prevent dangling pointer
        mpv_set_wakeup_callback(mpv, nil, nil)

        // Stop playback first
        command("stop")

        // Remove metal layer from view to stop rendering
        metalLayer.removeFromSuperlayer()

        // Tell MPV to quit gracefully - this flushes GPU commands
        command("quit")

        // Wait for GPU to finish all pending commands
        // MoltenVK needs time to complete Vulkan->Metal translation
        // This is longer in simulator due to software rendering
        #if targetEnvironment(simulator)
        Thread.sleep(forTimeInterval: 0.5)
        #else
        Thread.sleep(forTimeInterval: 0.2)
        #endif

        // Now safe to destroy
        mpv_terminate_destroy(mpv)
        mpv = nil
    }

    // MARK: - MPV Setup

    private func setupMpv() {
        mpv = mpv_create()
        guard mpv != nil else {
            print("Failed to create MPV context")
            return
        }

        // Logging
        #if DEBUG
        checkError(mpv_request_log_messages(mpv, "info"))
        #else
        checkError(mpv_request_log_messages(mpv, "no"))
        #endif

        // Rendering - use different settings for simulator vs device
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &metalLayer))

        if isSimulator {
            // Simulator: Use 'gpu' renderer (more stable with MoltenVK)
            checkError(mpv_set_option_string(mpv, "vo", "gpu"))
            checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"))
            checkError(mpv_set_option_string(mpv, "hwdec", "no"))  // No hardware decode in simulator
            checkError(mpv_set_option_string(mpv, "vulkan-swap-mode", "fifo"))  // Sync mode for stability
            print("🎬 MPV: Using simulator-safe settings (gpu + software decode)")
        } else {
            // Real device: Use gpu-next with HDR passthrough
            checkError(mpv_set_option_string(mpv, "vo", "gpu-next"))
            checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"))
            checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"))
            checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))  // HDR passthrough
            print("🎬 MPV: Using device settings (gpu-next + VideoToolbox + HDR)")
        }

        // Subtitles
        checkError(mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(mpv, "subs-fallback", "yes"))
        checkError(mpv_set_option_string(mpv, "sub-auto", "fuzzy"))

        // Performance
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"))
        checkError(mpv_set_option_string(mpv, "ytdl", "no"))

        // Network
        checkError(mpv_set_option_string(mpv, "demuxer-lavf-o", "reconnect=1,reconnect_streamed=1"))
        checkError(mpv_set_option_string(mpv, "cache", "yes"))
        checkError(mpv_set_option_string(mpv, "demuxer-max-bytes", "150MiB"))
        checkError(mpv_set_option_string(mpv, "demuxer-max-back-bytes", "75MiB"))

        checkError(mpv_initialize(mpv))

        // Observe properties
        mpv_observe_property(mpv, 0, MPVProperty.pause, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.coreIdle, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.eofReached, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.seeking, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.duration, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.trackListCount, MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsSigPeak, MPV_FORMAT_DOUBLE)

        // Setup wakeup callback
        mpv_set_wakeup_callback(mpv, { ctx in
            let client = unsafeBitCast(ctx, to: MPVMetalViewController.self)
            client.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    // MARK: - Playback Controls

    func loadFile(_ url: URL) {
        guard mpv != nil else { return }

        updateState(.loading)

        var args = [url.absoluteString, "replace"]

        // Add HTTP headers if provided
        if let headers = httpHeaders, !headers.isEmpty {
            let headerString = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
            setString("http-header-fields", headerString)
        }

        command("loadfile", args: args)

        // Seek to start position after loading
        if let startTime = startTime, startTime > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.seek(to: startTime)
            }
        }
    }

    func play() {
        setFlag(MPVProperty.pause, false)
    }

    func pause() {
        setFlag(MPVProperty.pause, true)
    }

    func togglePause() {
        getFlag(MPVProperty.pause) ? play() : pause()
    }

    func stop() {
        command("stop")
        updateState(.idle)
    }

    func seek(to seconds: Double) {
        guard mpv != nil else { return }
        command("seek", args: [String(seconds), "absolute"])
    }

    func seekRelative(by seconds: Double) {
        guard mpv != nil else { return }
        command("seek", args: [String(seconds), "relative"])
    }

    // MARK: - Track Selection

    func selectAudioTrack(_ trackId: Int) {
        setInt(MPVProperty.aid, Int64(trackId))
    }

    func selectSubtitleTrack(_ trackId: Int?) {
        if let id = trackId {
            setInt(MPVProperty.sid, Int64(id))
        } else {
            setString(MPVProperty.sid, "no")
        }
    }

    func disableSubtitles() {
        setString(MPVProperty.sid, "no")
    }

    // MARK: - Audio Control

    var isMuted: Bool {
        getFlag(MPVProperty.mute)
    }

    func setMuted(_ muted: Bool) {
        setFlag(MPVProperty.mute, muted)
    }

    // MARK: - Property Getters

    var currentTime: Double {
        getDouble(MPVProperty.timePos)
    }

    var duration: Double {
        getDouble(MPVProperty.duration)
    }

    var isPlaying: Bool {
        !getFlag(MPVProperty.pause) && !getFlag(MPVProperty.coreIdle)
    }

    var isPaused: Bool {
        getFlag(MPVProperty.pause)
    }

    var playbackRate: Float {
        get { Float(getDouble(MPVProperty.speed)) }
        set { setDouble(MPVProperty.speed, Double(newValue)) }
    }

    // MARK: - Track Enumeration

    func getTracks() -> (audio: [MPVTrack], subtitles: [MPVTrack]) {
        guard mpv != nil else { return ([], []) }

        var audioTracks: [MPVTrack] = []
        var subtitleTracks: [MPVTrack] = []

        let count = Int(getInt(MPVProperty.trackListCount))

        for i in 0..<count {
            let prefix = "track-list/\(i)"

            guard let typeStr = getString("\(prefix)/type") else { continue }

            let type: MPVTrack.TrackType
            switch typeStr {
            case "audio": type = .audio
            case "sub": type = .subtitle
            case "video": type = .video
            default: continue
            }

            let track = MPVTrack(
                id: Int(getInt("\(prefix)/id")),
                type: type,
                title: getString("\(prefix)/title"),
                language: getString("\(prefix)/lang"),
                codec: getString("\(prefix)/codec"),
                isDefault: getFlag("\(prefix)/default"),
                isForced: getFlag("\(prefix)/forced"),
                isSelected: getFlag("\(prefix)/selected")
            )

            switch type {
            case .audio:
                audioTracks.append(track)
            case .subtitle:
                subtitleTracks.append(track)
            case .video:
                break
            }
        }

        return (audioTracks, subtitleTracks)
    }

    // MARK: - Event Handling

    private func readEvents() {
        queue.async { [weak self] in
            guard let self, self.mpv != nil, !self.isShuttingDown else { return }

            while self.mpv != nil && !self.isShuttingDown {
                let event = mpv_wait_event(self.mpv, 0)
                guard event?.pointee.event_id != MPV_EVENT_NONE else { break }

                self.handleEvent(event!.pointee)
            }
        }
    }

    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            handlePropertyChange(event)

        case MPV_EVENT_START_FILE:
            DispatchQueue.main.async { [weak self] in
                self?.updateState(.loading)
            }

        case MPV_EVENT_FILE_LOADED:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let tracks = self.getTracks()
                self.delegate?.mpvPlayerDidUpdateTracks(audio: tracks.audio, subtitles: tracks.subtitles)
                self.updateState(.playing)
            }

        case MPV_EVENT_PLAYBACK_RESTART:
            DispatchQueue.main.async { [weak self] in
                if self?.currentState == .buffering {
                    self?.updateState(.playing)
                }
            }

        case MPV_EVENT_END_FILE:
            let reason = event.data.assumingMemoryBound(to: mpv_event_end_file.self).pointee.reason
            DispatchQueue.main.async { [weak self] in
                if reason == MPV_END_FILE_REASON_EOF {
                    self?.updateState(.ended)
                } else if reason == MPV_END_FILE_REASON_ERROR {
                    self?.updateState(.error("Playback error"))
                    self?.delegate?.mpvPlayerDidEncounterError("Playback ended with error")
                }
            }

        case MPV_EVENT_SHUTDOWN:
            mpv_terminate_destroy(mpv)
            mpv = nil

        case MPV_EVENT_LOG_MESSAGE:
            #if DEBUG
            let msg = event.data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
            if let prefix = msg.prefix, let text = msg.text {
                print("[MPV \(String(cString: prefix))] \(String(cString: text))", terminator: "")
            }
            #endif

        default:
            break
        }
    }

    private func handlePropertyChange(_ event: mpv_event) {
        guard let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee,
              let name = property.name else { return }

        let propertyName = String(cString: name)

        switch propertyName {
        case MPVProperty.pause:
            let paused = property.data?.assumingMemoryBound(to: Int32.self).pointee ?? 0
            DispatchQueue.main.async { [weak self] in
                self?.updateState(paused != 0 ? .paused : .playing)
            }

        case MPVProperty.pausedForCache:
            let buffering = property.data?.assumingMemoryBound(to: Int32.self).pointee ?? 0
            DispatchQueue.main.async { [weak self] in
                if buffering != 0 {
                    self?.updateState(.buffering)
                } else if self?.currentState == .buffering {
                    self?.updateState(.playing)
                }
            }

        case MPVProperty.timePos, MPVProperty.duration:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.mpvPlayerTimeDidChange(
                    current: self.currentTime,
                    duration: self.duration
                )
            }

        case MPVProperty.trackListCount:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let tracks = self.getTracks()
                self.delegate?.mpvPlayerDidUpdateTracks(audio: tracks.audio, subtitles: tracks.subtitles)
            }

        case MPVProperty.eofReached:
            let eof = property.data?.assumingMemoryBound(to: Int32.self).pointee ?? 0
            if eof != 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.updateState(.ended)
                }
            }

        default:
            break
        }
    }

    private func updateState(_ newState: MPVPlayerState) {
        guard currentState != newState else { return }
        currentState = newState
        delegate?.mpvPlayerDidChangeState(newState)
    }

    // MARK: - MPV Property Helpers

    private func command(_ command: String, args: [String] = []) {
        guard mpv != nil else { return }

        let allArgs = [command] + args
        var cStrings = allArgs.map { strdup($0) }
        cStrings.append(nil)
        defer { cStrings.compactMap { $0 }.forEach { free($0) } }

        cStrings.withUnsafeMutableBufferPointer { buffer in
            buffer.withMemoryRebound(to: UnsafePointer<CChar>?.self) { reboundBuffer in
                let result = mpv_command(mpv, reboundBuffer.baseAddress)
                if result < 0 {
                    print("MPV command '\(command)' failed: \(String(cString: mpv_error_string(result)))")
                }
            }
        }
    }

    private func getDouble(_ name: String) -> Double {
        guard mpv != nil else { return 0 }
        var data: Double = 0
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    private func setDouble(_ name: String, _ value: Double) {
        guard mpv != nil else { return }
        var data = value
        mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
    }

    private func getInt(_ name: String) -> Int64 {
        guard mpv != nil else { return 0 }
        var data: Int64 = 0
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
        return data
    }

    private func setInt(_ name: String, _ value: Int64) {
        guard mpv != nil else { return }
        var data = value
        mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
    }

    private func getFlag(_ name: String) -> Bool {
        guard mpv != nil else { return false }
        var data: Int32 = 0
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data != 0
    }

    private func setFlag(_ name: String, _ value: Bool) {
        guard mpv != nil else { return }
        var data: Int32 = value ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func getString(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        guard let cstr = mpv_get_property_string(mpv, name) else { return nil }
        let str = String(cString: cstr)
        mpv_free(cstr)
        return str
    }

    private func setString(_ name: String, _ value: String) {
        guard mpv != nil else { return }
        mpv_set_property_string(mpv, name, value)
    }

    private func checkError(_ status: CInt) {
        if status < 0 {
            print("MPV error: \(String(cString: mpv_error_string(status)))")
        }
    }
}
