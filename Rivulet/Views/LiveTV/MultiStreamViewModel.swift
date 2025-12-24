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
    @Published var focusedSlotIndex: Int = 0
    @Published var showControls = true
    @Published var showChannelPicker = false

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
        streams.count < 4
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

        // Start playback
        if let url = LiveTVDataStore.shared.buildStreamURL(for: channel) {
            do {
                try await wrapper.load(url: url, headers: [:], startTime: nil)
                wrapper.setMuted(isMuted)
                wrapper.play()
                print("📺 MultiStream: Added channel '\(channel.name)' at slot \(slotIndex), muted: \(isMuted)")
            } catch {
                print("📺 MultiStream: Failed to load '\(channel.name)': \(error)")
            }
        }

        showChannelPicker = false
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

        showControlsTemporarily()
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

    private func startControlsHideTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: controlsHideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Only hide if all streams are playing
                let allPlaying = self.streams.allSatisfy { $0.playbackState == .playing }
                if allPlaying {
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.showControls = false
                    }
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
