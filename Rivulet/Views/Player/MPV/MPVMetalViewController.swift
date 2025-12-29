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

    /// Enable lightweight mode for live streams (smaller buffers, simpler rendering)
    var isLiveStreamMode: Bool = false

    private var timeObserverActive = false
    private var currentState: MPVPlayerState = .idle
    private var isShuttingDown = false
    private var lastKnownSize: CGSize = .zero
    private var previousDrawableSize: CGSize = .zero
    private var resizeWorkItem: DispatchWorkItem?

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

    private var hasSetupMpv = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Ensure the view clips its contents to bounds
        view.clipsToBounds = true
        view.layer.masksToBounds = true

        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor

        view.layer.addSublayer(metalLayer)

        // Don't setup MPV here - wait for viewDidLayoutSubviews when we have proper bounds
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let newSize = view.bounds.size

        // Update metal layer frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = view.bounds
        CATransaction.commit()

        // Setup MPV after we have proper bounds (not .zero)
        if !hasSetupMpv && newSize.width > 0 && newSize.height > 0 {
            hasSetupMpv = true
            lastKnownSize = newSize
            setupMpv()

            if let url = playUrl {
                loadFile(url)
            }
        }
        // If size changed significantly after MPV is setup, force a resize (debounced)
        else if hasSetupMpv && mpv != nil && !isShuttingDown {
            let sizeDelta = abs(newSize.width - lastKnownSize.width) + abs(newSize.height - lastKnownSize.height)
            if sizeDelta > 10 {  // More than 10pt change
                lastKnownSize = newSize

                // Cancel any pending resize and schedule a new one
                // This debounces rapid size changes during animations
                resizeWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.forceVideoResize()
                }
                resizeWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
            }
        }
    }

    /// Force MPV to re-evaluate its output size when container resizes
    private func forceVideoResize() {
        guard mpv != nil, !isShuttingDown else { return }

        let currentDrawable = metalLayer.drawableSize
        let isGrowing = currentDrawable.width > previousDrawableSize.width ||
                        currentDrawable.height > previousDrawableSize.height

        print("🎬 MPV: Forcing video resize to \(lastKnownSize), drawable: \(previousDrawableSize) -> \(currentDrawable), growing: \(isGrowing)")

        // Force the Metal layer to redraw at new size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.setNeedsDisplay()
        CATransaction.commit()

        // For live streams when shrinking, skip the aggressive reconfigure - GPU scaling is sufficient
        // This prevents visual glitches when resizing in multiview
        // But when GROWING, we must tell MPV to render at the new larger size
        if isLiveStreamMode && !isGrowing {
            previousDrawableSize = currentDrawable
            return
        }

        previousDrawableSize = currentDrawable

        // Tell MPV to reconfigure by toggling a harmless property
        queue.async { [weak self] in
            guard let self, self.mpv != nil, !self.isShuttingDown else { return }

            // Toggle video-sync which forces vo reconfiguration without affecting playback
            let currentSync = self.getString("video-sync") ?? "audio"
            self.setString("video-sync", "display-resample")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.mpv != nil, !self.isShuttingDown else { return }
                self.queue.async {
                    self.setString("video-sync", currentSync)
                }
            }
        }
    }

    /// Explicitly handle container size changes initiated by SwiftUI layout updates
    func updateForContainerSize(_ newSize: CGSize) {
        guard !isShuttingDown, newSize != .zero else { return }

        // Keep view/frame and Metal layer in sync with the new container size
        if view.bounds.size != newSize {
            view.bounds = CGRect(origin: .zero, size: newSize)
            view.frame = CGRect(origin: view.frame.origin, size: newSize)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = CGRect(origin: .zero, size: newSize)
        // Pick a drawable size that matches the view aspect, is large enough for MPV blits,
        // and never exceeds the screen's native size. We don't downscale below the view size
        // to avoid triggering Metal validation on large copies.
        let screenSize = UIScreen.main.nativeBounds.size
        let baseWidth = max(newSize.width * metalLayer.contentsScale, 1)
        let baseHeight = max(newSize.height * metalLayer.contentsScale, 1)
        // Clamp strictly to screen to avoid oversized blits; no expansion beyond needed
        let targetSize = CGSize(
            width: min(screenSize.width, baseWidth),
            height: min(screenSize.height, baseHeight)
        )

        // For live streams: only grow the drawable, never shrink it while rendering.
        // Shrinking can cause Metal validation errors when MPV's render pass is still
        // configured for the old larger size. The frame shrinks (for display) but the
        // drawable stays at the max size to avoid renderTargetWidth > attachmentWidth.
        let currentDrawable = metalLayer.drawableSize
        let safeTargetSize: CGSize
        if isLiveStreamMode && hasSetupMpv {
            safeTargetSize = CGSize(
                width: max(currentDrawable.width, targetSize.width),
                height: max(currentDrawable.height, targetSize.height)
            )
        } else {
            safeTargetSize = targetSize
        }

        if metalLayer.drawableSize != safeTargetSize {
            metalLayer.drawableSize = safeTargetSize
        }
        CATransaction.commit()

        view.setNeedsLayout()
        view.layoutIfNeeded()

        print("🎬 MPV: updateForContainerSize new=\(newSize), bounds=\(view.bounds.size), frame=\(view.frame.size), layer=\(metalLayer.frame.size), drawable=\(metalLayer.drawableSize), scale=\(metalLayer.contentsScale), screen=\(UIScreen.main.nativeBounds.size)")

        lastKnownSize = newSize

        if hasSetupMpv && mpv != nil {
            forceVideoResize()
        }
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

        // Stop playback first - this begins GPU resource cleanup
        command("stop")

        #if targetEnvironment(simulator)
        // Simulator: MoltenVK software rendering needs more time for GPU flush
        // Wait for in-flight commands before any layer modifications
        Thread.sleep(forTimeInterval: 0.3)
        #endif

        // Tell MPV to quit gracefully BEFORE removing layer
        // This allows MPV to properly flush Vulkan command queues
        command("quit")

        #if targetEnvironment(simulator)
        // Wait for MPV to process quit and flush GPU commands
        // MoltenVK command buffer completion is slower in simulator
        Thread.sleep(forTimeInterval: 1.0)
        #else
        Thread.sleep(forTimeInterval: 0.2)
        #endif

        // NOW remove metal layer - after GPU work is complete
        if Thread.isMainThread {
            metalLayer.removeFromSuperlayer()
        } else {
            DispatchQueue.main.sync {
                metalLayer.removeFromSuperlayer()
            }
        }

        #if targetEnvironment(simulator)
        // Final wait for any deferred cleanup
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
            // Real device: Use gpu-next with native Metal backend (avoid MoltenVK on device)
            checkError(mpv_set_option_string(mpv, "vo", "gpu-next"))
            checkError(mpv_set_option_string(mpv, "gpu-api", "metal"))
            checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"))  // Zero-copy hardware decode
            checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))  // HDR passthrough

            // GPU optimizations - minimize CPU work
            checkError(mpv_set_option_string(mpv, "gpu-hwdec-interop", "videotoolbox"))  // Keep frames on GPU
            checkError(mpv_set_option_string(mpv, "opengl-pbo", "yes"))  // Async texture upload

            print("🎬 MPV: Using device settings (gpu-next + Metal + VideoToolbox + HDR)")
        }

        // Audio configuration
        // Force 5.1 max to avoid audiounit sp255-sp255 bug with 8-channel layouts
        // This affects PCM output; passthrough codecs bypass this entirely
        checkError(mpv_set_option_string(mpv, "audio-channels", "5.1"))

        // Force downmix of 7.1 to 5.1 to avoid audiounit crash with 8 channels
        checkError(mpv_set_option_string(mpv, "af", "lavfi=[aformat=channel_layouts=5.1|stereo]"))

        // Audio buffer for smoother playback (default ~0.2s can cause stuttering with high-bitrate content)
        // Note: This option may not be available in all MPV builds - fail silently
        let audioBufferResult = mpv_set_option_string(mpv, "audio-buffer", "0.5")
        if audioBufferResult < 0 {
            print("🎬 MPV: audio-buffer option not available (error \(audioBufferResult)), using default")
        }

        let useAirPlayAudio = UserDefaults.standard.bool(forKey: "useAirPlayAudio")
        if useAirPlayAudio {
            // AirPlay/HomePod: 5.1 is already set, no passthrough possible
            print("🎬 MPV: Using AirPlay audio mode (5.1 channels)")
        } else {
            // HDMI receiver: Enable passthrough for compressed surround formats
            // These bypass the channel limit and go directly to receiver
            checkError(mpv_set_option_string(mpv, "audio-spdif", "ac3,eac3,dts-hd,truehd"))
            print("🎬 MPV: Using HDMI mode (5.1 PCM, passthrough for AC3/DTS/TrueHD)")
        }

        // Subtitles - use standard MPV options
        checkError(mpv_set_option_string(mpv, "sub-auto", "fuzzy"))
        checkError(mpv_set_option_string(mpv, "slang", "en,eng"))  // Prefer English subtitles

        // Performance
        // video-rotate=0 means no rotation
        checkError(mpv_set_option_string(mpv, "video-rotate", "0"))
        // Disable youtube-dl integration (not needed, saves startup time)
        mpv_set_option_string(mpv, "ytdl", "no")  // May not exist in all builds

        // Network & buffering - use smaller buffers for live streams to reduce CPU/memory
        checkError(mpv_set_option_string(mpv, "demuxer-lavf-o", "reconnect=1,reconnect_streamed=1"))
        if isLiveStreamMode {
            // Live TV: minimal buffering, no back-buffer (can't seek anyway)
            checkError(mpv_set_option_string(mpv, "cache", "yes"))
            checkError(mpv_set_option_string(mpv, "demuxer-max-bytes", "32MiB"))
            checkError(mpv_set_option_string(mpv, "demuxer-max-back-bytes", "0"))
            checkError(mpv_set_option_string(mpv, "cache-secs", "10"))
            checkError(mpv_set_option_string(mpv, "demuxer-readahead-secs", "5"))

            // Reduce CPU overhead for live streams
            checkError(mpv_set_option_string(mpv, "vd-lavc-threads", "1"))  // Single decode thread (HW does the work)
            checkError(mpv_set_option_string(mpv, "scale", "bilinear"))  // Fast GPU scaling
            checkError(mpv_set_option_string(mpv, "dscale", "bilinear"))  // Fast downscaling
            checkError(mpv_set_option_string(mpv, "dither", "no"))  // Disable dithering
            checkError(mpv_set_option_string(mpv, "correct-downscaling", "no"))  // Skip correction
            checkError(mpv_set_option_string(mpv, "linear-downscaling", "no"))  // Skip linear light
            checkError(mpv_set_option_string(mpv, "deband", "no"))  // No debanding
            checkError(mpv_set_option_string(mpv, "interpolation", "no"))  // No frame interpolation

            print("🎬 MPV: Using live stream optimized settings (minimal processing, GPU scaling)")
        } else {
            // VOD: larger buffers for smooth playback
            checkError(mpv_set_option_string(mpv, "cache", "yes"))
            checkError(mpv_set_option_string(mpv, "demuxer-max-bytes", "150MiB"))
            checkError(mpv_set_option_string(mpv, "demuxer-max-back-bytes", "75MiB"))
        }

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
        // Trigger full shutdown to ensure clean state for next player instance
        shutdownMpv()
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
