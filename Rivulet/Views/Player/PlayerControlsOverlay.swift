//
//  PlayerControlsOverlay.swift
//  Rivulet
//
//  Native tvOS-style player controls with transport bar and swipe-down info panel
//

import SwiftUI

struct PlayerControlsOverlay: View {
    @ObservedObject var viewModel: UniversalPlayerViewModel

    @State private var showInfoPanel = false
    @State private var selectedInfoTab: InfoTab = .info

    enum InfoTab: String, CaseIterable {
        case info = "Info"
        case audio = "Audio"
        case subtitles = "Subtitles"
    }

    var body: some View {
        ZStack {
            // Transport bar at bottom
            VStack {
                Spacer()
                transportBar
            }

            // Info panel overlay (swipe down to show)
            if showInfoPanel {
                infoPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        #if os(tvOS)
        .onMoveCommand { direction in
            handleMoveCommand(direction)
        }
        .onExitCommand {
            handleExitCommand()
        }
        .onPlayPauseCommand {
            viewModel.togglePlayPause()
        }
        #endif
    }

    // MARK: - Transport Bar (Bottom)

    private var transportBar: some View {
        VStack(spacing: 16) {
            // Title (shows briefly at top of transport area)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let subtitle = viewModel.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                Spacer()

                // Playback state indicator
                if viewModel.isBuffering {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
            }
            .padding(.horizontal, 80)

            // Progress bar
            TransportProgressBar(
                currentTime: viewModel.currentTime,
                duration: viewModel.duration,
                isFocused: false,
                onSeek: { time in
                    Task { await viewModel.seek(to: time) }
                }
            )
            .padding(.horizontal, 80)
            .padding(.bottom, 50)
        }
        .padding(.vertical, 30)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Info Panel (Swipe Down)

    private var infoPanel: some View {
        VStack(spacing: 0) {
            // Panel content
            VStack(spacing: 24) {
                // Close indicator
                Capsule()
                    .fill(.white.opacity(0.4))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)

                // Tab selector
                HStack(spacing: 32) {
                    ForEach(InfoTab.allCases, id: \.self) { tab in
                        InfoTabButton(
                            title: tab.rawValue,
                            isSelected: selectedInfoTab == tab,
                            isEnabled: isTabEnabled(tab)
                        ) {
                            if isTabEnabled(tab) {
                                selectedInfoTab = tab
                            }
                        }
                    }
                }
                .padding(.horizontal, 60)

                // Tab content
                Group {
                    switch selectedInfoTab {
                    case .info:
                        infoTabContent
                    case .audio:
                        audioTabContent
                    case .subtitles:
                        subtitlesTabContent
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(.horizontal, 60)
                .padding(.bottom, 40)
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            )
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))

            Spacer()
        }
        .padding(.top, 60)
    }

    // MARK: - Info Tab Content

    private var infoTabContent: some View {
        HStack(alignment: .top, spacing: 40) {
            // Metadata
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                if let subtitle = viewModel.subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Runtime
                if viewModel.duration > 0 {
                    Text(formatDuration(viewModel.duration))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            // Current track info
            VStack(alignment: .trailing, spacing: 12) {
                if let audioTrack = currentAudioTrack {
                    Label(audioTrack.displayName, systemImage: "speaker.wave.2")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                if let subtitleTrack = currentSubtitleTrack {
                    Label(subtitleTrack.displayName, systemImage: "captions.bubble")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                } else if !viewModel.subtitleTracks.isEmpty {
                    Label("Off", systemImage: "captions.bubble")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Audio Tab Content

    private var audioTabContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(viewModel.audioTracks) { track in
                    TrackCard(
                        title: track.displayName,
                        subtitle: track.codec?.uppercased(),
                        isSelected: track.id == viewModel.currentAudioTrackId
                    ) {
                        viewModel.selectAudioTrack(id: track.id)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Subtitles Tab Content

    private var subtitlesTabContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Off option
                TrackCard(
                    title: "Off",
                    subtitle: nil,
                    isSelected: viewModel.currentSubtitleTrackId == nil
                ) {
                    viewModel.selectSubtitleTrack(id: nil)
                }

                ForEach(viewModel.subtitleTracks) { track in
                    TrackCard(
                        title: track.displayName,
                        subtitle: track.codec?.uppercased(),
                        isSelected: track.id == viewModel.currentSubtitleTrackId
                    ) {
                        viewModel.selectSubtitleTrack(id: track.id)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Helpers

    private func isTabEnabled(_ tab: InfoTab) -> Bool {
        switch tab {
        case .info: return true
        case .audio: return viewModel.audioTracks.count > 1
        case .subtitles: return !viewModel.subtitleTracks.isEmpty
        }
    }

    private var currentAudioTrack: MediaTrack? {
        viewModel.audioTracks.first { $0.id == viewModel.currentAudioTrackId }
    }

    private var currentSubtitleTrack: MediaTrack? {
        guard let id = viewModel.currentSubtitleTrackId else { return nil }
        return viewModel.subtitleTracks.first { $0.id == id }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }

    #if os(tvOS)
    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .down:
            if !showInfoPanel {
                withAnimation(.easeOut(duration: 0.3)) {
                    showInfoPanel = true
                }
            }
        case .up:
            if showInfoPanel {
                withAnimation(.easeOut(duration: 0.3)) {
                    showInfoPanel = false
                }
            }
        case .left:
            // Always seek backward
            Task { await viewModel.seekRelative(by: -10) }
        case .right:
            // Always seek forward
            Task { await viewModel.seekRelative(by: 10) }
        @unknown default:
            break
        }
    }

    private func handleExitCommand() {
        if showInfoPanel {
            withAnimation(.easeOut(duration: 0.3)) {
                showInfoPanel = false
            }
        }
    }
    #endif
}

// MARK: - Transport Progress Bar

private struct TransportProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isFocused: Bool
    let onSeek: (TimeInterval) -> Void  // Kept for future use

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var body: some View {
        VStack(spacing: 8) {
            // Progress track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Capsule()
                        .fill(.white.opacity(0.3))

                    // Progress fill
                    Capsule()
                        .fill(.white)
                        .frame(width: max(0, geometry.size.width * progress))

                    // Playhead
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .offset(x: max(0, min(geometry.size.width - 16, geometry.size.width * progress - 8)))
                }
            }
            .frame(height: 6)

            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Spacer()

                Text("-\(formatTime(max(0, duration - currentTime)))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Info Tab Button

private struct InfoTabButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .fontWeight(isSelected ? .bold : .medium)
                .foregroundStyle(isEnabled ? (isSelected ? .white : .white.opacity(0.6)) : .white.opacity(0.3))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? .white.opacity(0.2) : .clear)
                )
        }
        .buttonStyle(.plain)
        .focusable(isEnabled)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Track Card

private struct TrackCard: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                }

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(16)
            .frame(minWidth: 180)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? .white.opacity(0.15) : .white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isFocused ? .white : .clear, lineWidth: 3)
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        Text("Video Content")
            .foregroundStyle(.white.opacity(0.3))
    }
}
