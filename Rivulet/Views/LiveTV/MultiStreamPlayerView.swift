//
//  MultiStreamPlayerView.swift
//  Rivulet
//
//  Multi-stream Live TV player with 2x2 grid layout
//

import SwiftUI

struct MultiStreamPlayerView: View {
    @StateObject private var viewModel: MultiStreamViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedIndex: Int?

    init(initialChannel: UnifiedChannel) {
        _viewModel = StateObject(wrappedValue: MultiStreamViewModel(initialChannel: initialChannel))
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Stream grid
            streamGrid

            // Controls overlay
            if viewModel.showControls {
                MultiStreamControlsOverlay(
                    viewModel: viewModel,
                    onDismiss: { dismissPlayer() }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }

            // Channel picker
            if viewModel.showChannelPicker {
                ChannelPickerSheet(
                    excludedChannelIds: viewModel.activeChannelIds,
                    onSelect: { channel in
                        Task {
                            await viewModel.addChannel(channel)
                        }
                    },
                    onDismiss: {
                        viewModel.showChannelPicker = false
                    }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
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
            viewModel.togglePlayPauseOnFocused()
            viewModel.showControlsTemporarily()
        }
        .onExitCommand {
            handleExitCommand()
        }
        #endif
        .onChange(of: focusedIndex) { _, newIndex in
            if let index = newIndex {
                viewModel.setFocus(to: index)
            }
        }
        .onAppear {
            // Set initial focus
            focusedIndex = 0
        }
        .onDisappear {
            viewModel.stopAllStreams()
        }
    }

    // MARK: - Stream Grid

    private var streamGrid: some View {
        GeometryReader { geometry in
            let layout = gridLayout(for: viewModel.streamCount)
            let spacing: CGFloat = 8
            let slotWidth = (geometry.size.width - CGFloat(layout.columns - 1) * spacing) / CGFloat(layout.columns)
            let slotHeight = (geometry.size.height - CGFloat(layout.rows - 1) * spacing) / CGFloat(layout.rows)

            VStack(spacing: spacing) {
                ForEach(0..<layout.rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<layout.columns, id: \.self) { col in
                            let index = row * layout.columns + col

                            if index < viewModel.streams.count {
                                let slot = viewModel.streams[index]

                                StreamSlotView(
                                    slot: slot,
                                    index: index,
                                    isFocused: focusedIndex == index,
                                    onControllerReady: { controller in
                                        viewModel.setPlayerController(controller, for: slot.id)
                                    }
                                )
                                .frame(width: slotWidth, height: slotHeight)
                                .focusable()
                                .focused($focusedIndex, equals: index)
                            } else {
                                // Empty slot placeholder
                                emptySlot
                                    .frame(width: slotWidth, height: slotHeight)
                            }
                        }
                    }
                }
            }
        }
        .padding(0)
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(white: 0.1))
    }

    // MARK: - Grid Layout

    private func gridLayout(for count: Int) -> (rows: Int, columns: Int) {
        switch count {
        case 0, 1:
            return (1, 1)  // Full screen
        case 2:
            return (1, 2)  // Side by side
        case 3, 4:
            return (2, 2)  // 2x2 grid
        default:
            return (2, 2)
        }
    }

    // MARK: - Input Handling

    #if os(tvOS)
    private func handleExitCommand() {
        if viewModel.showChannelPicker {
            // Close channel picker first
            viewModel.showChannelPicker = false
        } else if viewModel.showControls {
            // Hide controls
            withAnimation(.easeOut(duration: 0.2)) {
                viewModel.showControls = false
            }
        } else {
            // Exit player
            dismissPlayer()
        }
    }
    #endif

    private func dismissPlayer() {
        viewModel.stopAllStreams()
        dismiss()
    }
}

#Preview {
    MultiStreamPlayerView(
        initialChannel: UnifiedChannel(
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
        )
    )
}
