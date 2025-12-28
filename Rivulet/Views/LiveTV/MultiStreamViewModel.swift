//
//  MultiStreamViewModel.swift
//  Rivulet
//
//  Central state management for multi-stream Live TV playback
//

import SwiftUI
import Combine

@MainActor
final class MultiStreamViewModel: ObservableObject {

    enum LayoutMode: Equatable {
        case grid
        case focus(mainId: UUID)
    }

    // MARK: - Stream Slot Model

    struct StreamSlot: Identifiable {
        let id = UUID()
        let channel: UnifiedChannel
        let playerWrapper: MPVPlayerWrapper
        var playerController: MPVMetalViewController?
        var playbackState: UniversalPlaybackState = .idle
        var currentProgram: UnifiedProgram?
        var isMuted: Bool
    }

    // MARK: - Published State

    @Published private(set) var streams: [StreamSlot] = []
    @Published var focusedSlotIndex: Int = 0 {
        didSet {
            print("📺 focusedSlotIndex changed: \(oldValue) → \(focusedSlotIndex)")
        }
    }
    @Published var showControls = true
    @Published var showChannelPicker = false {
        didSet {
            if showChannelPicker {
                // Picker opened - cancel timer so controls don't hide while browsing
                controlsTimer?.invalidate()
                controlsTimer = nil
            } else if oldValue && !showChannelPicker {
                // Picker closed - restart timer to hide controls
                startControlsHideTimer()
            }
        }
    }
    @Published var layoutMode: LayoutMode = .grid

    // MARK: - Private State

    private var cancellables: [UUID: Set<AnyCancellable>] = [:]
    private var controlsTimer: Timer?
    private let controlsHideDelay: TimeInterval = 5

    // MARK: - Computed Properties

    var focusedStream: StreamSlot? {
        guard focusedSlotIndex >= 0, focusedSlotIndex < streams.count else { return nil }
        return streams[focusedSlotIndex]
    }

    var canAddStream: Bool {
        #if targetEnvironment(simulator)
        // Multiview disabled on simulator - MoltenVK can't handle multiple Vulkan instances
        return false
        #else
        return streams.count < 4
        #endif
    }

    var activeChannelIds: Set<String> {
        Set(streams.map { $0.channel.id })
    }

    var streamCount: Int {
        streams.count
    }

    // MARK: - Initialization

    init(initialChannel: UnifiedChannel) {
        // Add the initial channel (unmuted since it's first)
        Task {
            await addChannel(initialChannel)
        }
    }

    // MARK: - Stream Management

    func addChannel(_ channel: UnifiedChannel) async {
        guard canAddStream else { return }
        guard !activeChannelIds.contains(channel.id) else { return }

        // Close the picker immediately for responsiveness
        showChannelPicker = false

        // On simulator, we need to pause existing streams and wait before creating a new player
        // to avoid MoltenVK Metal texture crashes when multiple contexts are active
        #if targetEnvironment(simulator)
        if !streams.isEmpty {
            print("📺 MultiStream: Pausing existing streams before adding new one (simulator workaround)")

            // Pause all existing streams to reduce GPU contention
            for slot in streams {
                slot.playerWrapper.pause()
            }

            // Wait for GPU commands to complete
            try? await Task.sleep(for: .milliseconds(500))
        }
        #endif

        let wrapper = MPVPlayerWrapper()
        let isMuted = !streams.isEmpty  // First stream unmuted, others muted

        var slot = StreamSlot(
            channel: channel,
            playerWrapper: wrapper,
            isMuted: isMuted
        )

        // Load EPG data
        slot.currentProgram = LiveTVDataStore.shared.getCurrentProgram(for: channel)

        streams.append(slot)
        let slotIndex = streams.count - 1

        // Subscribe to playback state changes
        subscribeToSlot(at: slotIndex)

        // Reset custom layout if only one stream
        if streams.count <= 1 {
            layoutMode = .grid
        }

        // Start playback
        if let url = LiveTVDataStore.shared.buildStreamURL(for: channel) {
            do {
                try await wrapper.load(url: url, headers: [:], startTime: nil)
                wrapper.setMuted(isMuted)
                wrapper.play()
                print("📺 MultiStream: Added channel '\(channel.name)' at slot \(slotIndex), muted: \(isMuted)")

                #if targetEnvironment(simulator)
                // Resume other streams after new one is loading
                try? await Task.sleep(for: .milliseconds(300))
                for (idx, slot) in streams.enumerated() where idx != slotIndex {
                    slot.playerWrapper.play()
                }
                print("📺 MultiStream: Resumed existing streams")
                #endif
            } catch {
                print("📺 MultiStream: Failed to load '\(channel.name)': \(error)")
            }
        }
    }

    func removeStream(at index: Int) {
        guard index >= 0, index < streams.count else { return }

        let slot = streams[index]

        // Stop and cleanup player
        slot.playerWrapper.stop()

        // Remove subscriptions
        cancellables.removeValue(forKey: slot.id)

        // Remove from array
        streams.remove(at: index)

        print("📺 MultiStream: Removed stream at slot \(index)")

        // Reset layout if no streams or main stream removed
        if streams.count <= 1 {
            layoutMode = .grid
        } else if case .focus(let mainId) = layoutMode, !streams.contains(where: { $0.id == mainId }) {
            layoutMode = .grid
        }

        // Adjust focus if needed
        if streams.isEmpty {
            focusedSlotIndex = 0
        } else if focusedSlotIndex >= streams.count {
            setFocus(to: streams.count - 1)
        } else if index == focusedSlotIndex {
            // Removed the focused stream, make sure new focused has audio
            setFocus(to: focusedSlotIndex)
        }
    }

    func stopAllStreams() {
        for slot in streams {
            slot.playerWrapper.stop()
        }
        cancellables.removeAll()
        streams.removeAll()
        layoutMode = .grid
        print("📺 MultiStream: Stopped all streams")
    }

    // MARK: - Focus Management

    func setFocus(to newIndex: Int) {
        guard newIndex >= 0, newIndex < streams.count else { return }
        guard newIndex != focusedSlotIndex || streams[newIndex].isMuted else { return }

        // Mute previously focused stream
        if focusedSlotIndex >= 0, focusedSlotIndex < streams.count {
            streams[focusedSlotIndex].playerWrapper.setMuted(true)
            streams[focusedSlotIndex].isMuted = true
        }

        // Unmute newly focused stream
        streams[newIndex].playerWrapper.setMuted(false)
        streams[newIndex].isMuted = false

        focusedSlotIndex = newIndex

        print("📺 MultiStream: Focus changed to slot \(newIndex) ('\(streams[newIndex].channel.name)')")

        // Don't show controls when just switching focus - user uses Select to show controls
    }

    // MARK: - Layout

    func setFocusedLayout(on slotId: UUID) {
        guard streams.count > 1 else { return }
        layoutMode = .focus(mainId: slotId)
        if let index = streams.firstIndex(where: { $0.id == slotId }) {
            setFocus(to: index)
        }
    }

    func resetLayout() {
        layoutMode = .grid
    }

    // MARK: - Playback Controls

    func togglePlayPauseOnFocused() {
        guard let slot = focusedStream else { return }

        if slot.playerWrapper.isPlaying {
            slot.playerWrapper.pause()
        } else {
            slot.playerWrapper.play()
        }

        showControlsTemporarily()
    }

    func playAll() {
        for slot in streams {
            slot.playerWrapper.play()
        }
    }

    func pauseAll() {
        for slot in streams {
            slot.playerWrapper.pause()
        }
    }

    // MARK: - Controller Binding

    func setPlayerController(_ controller: MPVMetalViewController, for slotId: UUID) {
        guard let index = streams.firstIndex(where: { $0.id == slotId }) else { return }
        streams[index].playerController = controller
        streams[index].playerWrapper.setPlayerController(controller)

        // Apply mute state
        controller.setMuted(streams[index].isMuted)
    }

    // MARK: - Controls Visibility

    func showControlsTemporarily() {
        showControls = true
        startControlsHideTimer()
    }

    /// Reset the controls hide timer (call when user navigates between buttons)
    func resetControlsTimer() {
        guard showControls && !showChannelPicker else { return }
        startControlsHideTimer()
    }

    private func startControlsHideTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: controlsHideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Hide controls after timeout - user can press Select to show again
                // Note: Timer is cancelled when picker opens, so this won't fire during picker
                withAnimation(.easeOut(duration: 0.3)) {
                    self.showControls = false
                }
            }
        }
    }

    // MARK: - Subscriptions

    private func subscribeToSlot(at index: Int) {
        guard index >= 0, index < streams.count else { return }

        let slot = streams[index]
        var slotCancellables = Set<AnyCancellable>()

        slot.playerWrapper.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if let idx = self.streams.firstIndex(where: { $0.id == slot.id }) {
                    self.streams[idx].playbackState = state
                }
            }
            .store(in: &slotCancellables)

        cancellables[slot.id] = slotCancellables
    }

    // MARK: - Cleanup

    deinit {
        controlsTimer?.invalidate()
    }
}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
