//
//  PlayerControlsOverlay.swift
//  Rivulet
//
//  Native tvOS-style player controls with transport bar and swipe-down info panel
//

import SwiftUI

struct PlayerControlsOverlay: View {
    @ObservedObject var viewModel: UniversalPlayerViewModel

    /// When true, shows only the info panel. When false, shows only the transport bar.
    var showInfoPanel: Bool = false

    // Use InfoTab from viewModel
    private typealias InfoTab = UniversalPlayerViewModel.InfoTab

    var body: some View {
        ZStack {
            if showInfoPanel {
                // Info panel only
                infoPanel
            } else {
                // Transport bar at bottom only
                VStack {
                    Spacer()
                    transportBar
                }
            }
        }
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

            // Progress bar with scrubbing support
            TransportProgressBar(
                currentTime: viewModel.currentTime,
                duration: viewModel.duration,
                isScrubbing: viewModel.isScrubbing,
                scrubTime: viewModel.scrubTime,
                scrubSpeed: viewModel.scrubSpeed,
                scrubThumbnail: viewModel.scrubThumbnail
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
            // Tab bar - focus managed by viewModel
            HStack(spacing: 16) {
                ForEach(Array(viewModel.availableInfoTabs.enumerated()), id: \.element) { index, tab in
                    InfoPanelTab(
                        title: tab.rawValue,
                        isSelected: viewModel.selectedInfoTab == tab,
                        // Only show focus ring when focus is on tabs, not content
                        isFocused: viewModel.isInfoPanelFocusOnTabs && viewModel.focusedInfoTabIndex == index
                    )
                    .onTapGesture {
                        viewModel.focusedInfoTabIndex = index
                        viewModel.selectFocusedInfoTab()
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Tab content
            Group {
                switch viewModel.selectedInfoTab {
                case .info:
                    infoTabContent
                case .audio:
                    audioTabContent
                case .subtitles:
                    subtitlesTabContent
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 80)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .padding(.horizontal, 80)
        }
        .padding(.top, 48)  // Same margin as sidebar from left
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Note: Input is handled by UniversalPlayerView, not here
    }

    // MARK: - Info Tab Content

    private var infoTabContent: some View {
        HStack(alignment: .top, spacing: 40) {
            // Left side: Title and description
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                if let subtitle = viewModel.subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Summary/description if available
                if let summary = viewModel.metadata.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right side: Technical info
            VStack(alignment: .trailing, spacing: 8) {
                // Video info
                if let videoInfo = videoInfoString {
                    InfoBadge(icon: "film", text: videoInfo)
                }

                // HDR badge
                if let hdrInfo = hdrInfoString {
                    InfoBadge(icon: "sparkles", text: hdrInfo, highlight: true)
                }

                // Audio info
                if let audioInfo = audioInfoString {
                    InfoBadge(icon: "speaker.wave.2", text: audioInfo)
                }

                // File info
                if let fileInfo = fileInfoString {
                    InfoBadge(icon: "doc", text: fileInfo)
                }

                // Duration/Runtime
                if viewModel.duration > 0 {
                    InfoBadge(icon: "clock", text: formatDuration(viewModel.duration))
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Audio Tab Content

    private var audioTabContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(viewModel.audioTracks.enumerated()), id: \.element.id) { index, track in
                    TrackButton(
                        title: track.name,
                        subtitle: formatAudioTrackInfo(track),
                        isSelected: track.id == viewModel.currentAudioTrackId,
                        isFocused: !viewModel.isInfoPanelFocusOnTabs && viewModel.focusedContentIndex == index
                    ) {
                        viewModel.selectAudioTrack(id: track.id)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Subtitles Tab Content

    private var subtitlesTabContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Off option (index 0)
                TrackButton(
                    title: "Off",
                    subtitle: "Disabled",
                    isSelected: viewModel.currentSubtitleTrackId == nil,
                    isFocused: !viewModel.isInfoPanelFocusOnTabs && viewModel.focusedContentIndex == 0
                ) {
                    viewModel.selectSubtitleTrack(id: nil)
                }

                ForEach(Array(viewModel.subtitleTracks.enumerated()), id: \.element.id) { index, track in
                    TrackButton(
                        title: track.name,
                        subtitle: formatSubtitleTrackInfo(track),
                        isSelected: track.id == viewModel.currentSubtitleTrackId,
                        isFocused: !viewModel.isInfoPanelFocusOnTabs && viewModel.focusedContentIndex == index + 1
                    ) {
                        viewModel.selectSubtitleTrack(id: track.id)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Media Info Helpers

    private var videoInfoString: String? {
        guard let media = viewModel.metadata.Media?.first else { return nil }
        var parts: [String] = []

        // Resolution - prefer videoResolution field (handles ultrawide correctly)
        if let res = media.videoResolution {
            // Plex provides resolution like "1080p", "4k", "720p"
            let formatted = res.lowercased()
            if formatted.contains("4k") || formatted.contains("2160") {
                parts.append("4K")
            } else if formatted.contains("1080") {
                parts.append("1080p")
            } else if formatted.contains("720") {
                parts.append("720p")
            } else if formatted.contains("480") {
                parts.append("480p")
            } else {
                parts.append(res.uppercased())
            }
        } else if let height = media.height {
            // Fallback to height-based calculation
            if height >= 2160 {
                parts.append("4K")
            } else if height >= 1080 {
                parts.append("1080p")
            } else if height >= 720 {
                parts.append("720p")
            } else {
                parts.append("\(height)p")
            }
        }

        // Codec
        if let codec = media.videoCodec?.uppercased() {
            if codec.contains("HEVC") || codec.contains("H265") {
                parts.append("HEVC")
            } else if codec.contains("AVC") || codec.contains("H264") {
                parts.append("H.264")
            } else if codec.contains("AV1") {
                parts.append("AV1")
            } else {
                parts.append(codec)
            }
        }

        // Frame rate
        if let fps = media.videoFrameRate {
            if fps.contains("24") || fps.lowercased().contains("24p") {
                parts.append("24fps")
            } else if fps.contains("60") {
                parts.append("60fps")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var hdrInfoString: String? {
        guard let streams = viewModel.metadata.Media?.first?.Part?.first?.Stream else { return nil }
        let videoStream = streams.first { $0.isVideo }

        var hdrParts: [String] = []

        if videoStream?.isDolbyVision == true {
            hdrParts.append("Dolby Vision")
        } else if videoStream?.isHDR == true {
            hdrParts.append("HDR10")
        }

        if let bitDepth = videoStream?.bitDepth, bitDepth >= 10 {
            hdrParts.append("\(bitDepth)-bit")
        }

        return hdrParts.isEmpty ? nil : hdrParts.joined(separator: " · ")
    }

    private var audioInfoString: String? {
        guard let media = viewModel.metadata.Media?.first else { return nil }
        var parts: [String] = []

        // Codec
        if let codec = media.audioCodec?.uppercased() {
            if codec.contains("TRUEHD") {
                parts.append("TrueHD")
            } else if codec.contains("DTS") {
                if codec.contains("HD") {
                    parts.append("DTS-HD")
                } else {
                    parts.append("DTS")
                }
            } else if codec.contains("EAC3") || codec.contains("E-AC-3") {
                parts.append("Dolby Digital+")
            } else if codec.contains("AC3") {
                parts.append("Dolby Digital")
            } else if codec.contains("AAC") {
                parts.append("AAC")
            } else if codec.contains("FLAC") {
                parts.append("FLAC")
            } else {
                parts.append(codec)
            }
        }

        // Channels
        if let channels = media.audioChannels {
            if channels >= 8 {
                parts.append("7.1")
            } else if channels >= 6 {
                parts.append("5.1")
            } else if channels == 2 {
                parts.append("Stereo")
            } else if channels == 1 {
                parts.append("Mono")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var fileInfoString: String? {
        guard let part = viewModel.metadata.Media?.first?.Part?.first else { return nil }
        var parts: [String] = []

        // Container
        if let container = part.container?.uppercased() {
            parts.append(container)
        }

        // File size (use binary GiB to match Plex display)
        if let size = part.size {
            let gib = Double(size) / 1_073_741_824  // 2^30 bytes
            if gib >= 1 {
                parts.append(String(format: "%.2f GB", gib))
            } else {
                let mib = Double(size) / 1_048_576  // 2^20 bytes
                parts.append(String(format: "%.0f MB", mib))
            }
        }

        // Bitrate
        if let bitrate = viewModel.metadata.Media?.first?.bitrate {
            let mbps = Double(bitrate) / 1000
            parts.append(String(format: "%.1f Mbps", mbps))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatAudioTrackInfo(_ track: MediaTrack) -> String {
        var parts: [String] = []
        if let codec = track.codec?.uppercased() {
            parts.append(codec)
        }
        if let lang = track.language {
            parts.append(lang)
        }
        return parts.isEmpty ? "Audio" : parts.joined(separator: " · ")
    }

    private func formatSubtitleTrackInfo(_ track: MediaTrack) -> String {
        var parts: [String] = []
        if let codec = track.codec?.uppercased() {
            parts.append(codec)
        }
        if track.isForced {
            parts.append("Forced")
        }
        return parts.isEmpty ? "Subtitle" : parts.joined(separator: " · ")
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }
}

// MARK: - Info Badge

private struct InfoBadge: View {
    let icon: String
    let text: String
    var highlight: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(highlight ? .yellow : .white.opacity(0.7))
    }
}

// MARK: - Transport Progress Bar

private struct TransportProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    var isScrubbing: Bool = false
    var scrubTime: TimeInterval = 0
    var scrubSpeed: Int = 0
    var scrubThumbnail: UIImage?

    private var displayTime: TimeInterval {
        isScrubbing ? scrubTime : currentTime
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, displayTime / duration))
    }

    private var speedLabel: String? {
        guard scrubSpeed != 0 else { return nil }
        let magnitude = abs(scrubSpeed)
        let arrow = scrubSpeed > 0 ? "▶▶" : "◀◀"
        return "\(arrow) \(magnitude)×"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail preview when scrubbing
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Thumbnail positioned above progress bar
                    if isScrubbing {
                        let thumbnailX = max(80, min(geometry.size.width - 80, geometry.size.width * progress))

                        VStack(spacing: 8) {
                            // Thumbnail image (only show if available)
                            if let thumbnail = scrubThumbnail {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 240, height: 135)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
                            }
                            // No placeholder - just skip thumbnail if not available

                            // Speed indicator
                            if let speed = speedLabel {
                                Text(speed)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(.blue)
                                    )
                            }

                            // Time label
                            Text(formatTime(scrubTime))
                                .font(.title2)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(.black.opacity(0.8))
                                )

                            // Arrow pointing to playhead
                            Triangle()
                                .fill(.white)
                                .frame(width: 12, height: 8)
                        }
                        .position(x: thumbnailX, y: scrubThumbnail != nil ? -120 : -60)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
            }
            .frame(height: isScrubbing ? 0 : 0)  // Reserve no height, positioned above

            // Progress track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Capsule()
                        .fill(.white.opacity(0.3))

                    // Progress fill (current position in blue when scrubbing)
                    if isScrubbing {
                        // Show current position as dimmer
                        let currentProgress = duration > 0 ? min(1, max(0, currentTime / duration)) : 0
                        Capsule()
                            .fill(.white.opacity(0.5))
                            .frame(width: max(0, geometry.size.width * currentProgress))
                    }

                    // Scrub/current position fill
                    Capsule()
                        .fill(isScrubbing ? .blue : .white)
                        .frame(width: max(0, geometry.size.width * progress))

                    // Playhead
                    Circle()
                        .fill(isScrubbing ? .blue : .white)
                        .frame(width: isScrubbing ? 24 : 16, height: isScrubbing ? 24 : 16)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .offset(x: max(0, min(geometry.size.width - (isScrubbing ? 24 : 16), geometry.size.width * progress - (isScrubbing ? 12 : 8))))
                        .animation(.easeOut(duration: 0.15), value: isScrubbing)
                }
            }
            .frame(height: isScrubbing ? 10 : 6)
            .animation(.easeOut(duration: 0.15), value: isScrubbing)

            // Time labels
            HStack {
                Text(formatTime(displayTime))
                    .font(.caption)
                    .fontWeight(isScrubbing ? .bold : .medium)
                    .monospacedDigit()
                    .foregroundStyle(isScrubbing ? .blue : .white)

                Spacer()

                Text("-\(formatTime(max(0, duration - displayTime)))")
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

// MARK: - Info Panel Tab (Manual Focus)

/// Simple tab view that displays focus state from our FocusScopeManager
private struct InfoPanelTab: View {
    let title: String
    let isSelected: Bool
    let isFocused: Bool

    var body: some View {
        Text(title)
            .font(.body)
            .fontWeight(isSelected ? .semibold : .medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? .white.opacity(0.2) : .white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(isFocused ? 0.8 : 0), lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Track Button

private struct TrackButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    var isFocused: Bool = false  // Manual focus from viewModel
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minWidth: 180)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? .white.opacity(0.25) : .white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(isFocused ? 0.8 : 0), lineWidth: 3)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onTapGesture {
            action()
        }
    }
}

// MARK: - Focusable Button

private struct FocusableButton<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @FocusState private var isFocused: Bool

    var body: some View {
        content()
            // Simplified focus effect: removed brightness (CPU-intensive color matrix)
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(isFocused ? 0.8 : 0), lineWidth: 3)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .focusable()
            .focused($isFocused)
            .onTapGesture {
                action()
            }
            #if os(tvOS)
            .onPlayPauseCommand {
                action()
            }
            #endif
    }
}

// MARK: - Triangle Shape (for thumbnail arrow)

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        Text("Video Content")
            .foregroundStyle(.white.opacity(0.3))
    }
}
