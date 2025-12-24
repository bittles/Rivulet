//
//  MultiStreamControlsOverlay.swift
//  Rivulet
//
//  Controls overlay for multi-stream Live TV playback
//

import SwiftUI

struct MultiStreamControlsOverlay: View {
    @ObservedObject var viewModel: MultiStreamViewModel
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Gradient backgrounds
            gradientBackgrounds

            VStack {
                // Top bar - focused channel info
                topBar
                    .padding(.horizontal, 60)
                    .padding(.top, 50)

                Spacer()

                // Bottom controls
                bottomControls
                    .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Gradient Backgrounds

    private var gradientBackgrounds: some View {
        VStack {
            LinearGradient(
                colors: [.black.opacity(0.8), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)

            Spacer()

            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .top) {
            if let focusedStream = viewModel.focusedStream {
                // Channel logo
                if let logoURL = focusedStream.channel.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 60)
                        default:
                            channelIcon
                        }
                    }
                } else {
                    channelIcon
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        if let number = focusedStream.channel.channelNumber {
                            Text("\(number)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Text(focusedStream.channel.name)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)

                        if focusedStream.channel.isHD {
                            Text("HD")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.white)
                                )
                        }

                        // Live indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                            Text("LIVE")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.red)
                        }
                    }

                    if let program = focusedStream.currentProgram {
                        Text(program.title)
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.8))

                        Text(programTimeString(program))
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                // Stream count indicator
                streamCountBadge
            } else {
                // No focused stream
                Text("No stream selected")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
        }
    }

    private var channelIcon: some View {
        Image(systemName: "tv")
            .font(.system(size: 32))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 80, height: 60)
    }

    private var streamCountBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.7))

            Text("\(viewModel.streamCount)/4")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.15))
        )
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 32) {
            // Remove stream button
            if viewModel.streamCount > 1 {
                ControlButtonView(
                    icon: "minus.circle.fill",
                    label: "Remove"
                ) {
                    viewModel.removeStream(at: viewModel.focusedSlotIndex)
                }
            }

            // Play/Pause button
            ControlButtonView(
                icon: (viewModel.focusedStream?.playerWrapper.isPlaying ?? false) ? "pause.fill" : "play.fill",
                label: (viewModel.focusedStream?.playerWrapper.isPlaying ?? false) ? "Pause" : "Play",
                isLarge: true
            ) {
                viewModel.togglePlayPauseOnFocused()
            }

            // Add channel button
            if viewModel.canAddStream {
                ControlButtonView(
                    icon: "plus.circle.fill",
                    label: "Add"
                ) {
                    viewModel.showChannelPicker = true
                }
            }

            // Exit button
            ControlButtonView(
                icon: "arrow.down.right.and.arrow.up.left",
                label: "Exit"
            ) {
                onDismiss()
            }
        }
    }

    // MARK: - Helpers

    private func programTimeString(_ program: UnifiedProgram) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let start = formatter.string(from: program.startTime)
        let end = formatter.string(from: program.endTime)
        return "\(start) - \(end)"
    }
}

// MARK: - Control Button View

private struct ControlButtonView: View {
    let icon: String
    let label: String
    var isLarge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: isLarge ? 80 : 64, height: isLarge ? 80 : 64)

                    Image(systemName: icon)
                        .font(.system(size: isLarge ? 36 : 28))
                        .foregroundStyle(.white)
                }

                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        MultiStreamControlsOverlay(
            viewModel: MultiStreamViewModel(
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
            ),
            onDismiss: {}
        )
    }
}
