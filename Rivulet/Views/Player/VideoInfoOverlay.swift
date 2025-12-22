//
//  VideoInfoOverlay.swift
//  Rivulet
//
//  Apple-style overlay displaying detailed video file information
//

import SwiftUI

struct VideoInfoOverlay: View {
    let metadata: PlexMetadata
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            // Content card positioned in bottom-left
            VStack {
                Spacer()
                HStack {
                    contentCard
                        .padding(.leading, 60)
                        .padding(.bottom, 60)
                    Spacer()
                }
            }
        }
        // Dismiss on Menu button press
        .onExitCommand {
            isPresented = false
        }
    }
    
    private var contentCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                mediaDetailsSection
                if metadata.Media?.first?.Part != nil {
                    Divider()
                    partsSection
                }
                Divider()
                metadataSection
            }
            .padding(32)
        }
        .frame(maxWidth: 600, maxHeight: 700)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
        }
    }
    
    private var headerSection: some View {
        HStack {
            Text("Video Info")
                .font(.system(size: 32, weight: .bold))
            
            Spacer()
            
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private var mediaDetailsSection: some View {
        if let media = metadata.Media?.first {
            mediaInfoView(media: media)
        } else {
            Text("No media information available")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
        }
    }
    
    private func mediaInfoView(media: PlexMedia) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Media")
                .font(.system(size: 24, weight: .semibold))
            
            if let videoCodec = media.videoCodec {
                InfoRow(label: "Video Codec", value: videoCodec)
            }
            
            if let resolution = media.videoResolution {
                InfoRow(label: "Resolution", value: resolution)
            }
            
            if let width = media.width, let height = media.height {
                InfoRow(label: "Dimensions", value: "\(width) × \(height)")
            }
            
            if let aspectRatio = media.aspectRatio {
                InfoRow(label: "Aspect Ratio", value: String(format: "%.2f:1", aspectRatio))
            }
            
            if let frameRate = media.videoFrameRate {
                InfoRow(label: "Frame Rate", value: frameRate)
            }
            
            if let bitrate = media.bitrate {
                InfoRow(label: "Bitrate", value: formatBitrate(bitrate))
            }
            
            if let container = media.container {
                InfoRow(label: "Container", value: container)
            }
            
            if let audioCodec = media.audioCodec {
                InfoRow(label: "Audio Codec", value: audioCodec)
            }
            
            if let audioChannels = media.audioChannels {
                InfoRow(label: "Audio Channels", value: "\(audioChannels)")
            }
            
            if let duration = media.duration {
                InfoRow(label: "Duration", value: formatDuration(duration))
            }
        }
    }
    
    @ViewBuilder
    private var partsSection: some View {
        if let parts = metadata.Media?.first?.Part, !parts.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("File")
                    .font(.system(size: 24, weight: .semibold))
                
                ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                    partInfoView(part: part, index: index, totalParts: parts.count)
                }
            }
        }
    }
    
    @ViewBuilder
    private func partInfoView(part: PlexPart, index: Int, totalParts: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if totalParts > 1 {
                Text("Part \(index + 1)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            if let file = part.file {
                InfoRow(label: "File", value: file, isFile: true)
            }
            
            if let size = part.size {
                InfoRow(label: "File Size", value: formatFileSize(Int64(size)))
            }
            
            if let container = part.container {
                InfoRow(label: "Container", value: container)
            }
            
            if let duration = part.duration {
                InfoRow(label: "Duration", value: formatDuration(duration))
            }
            
            if index < totalParts - 1 {
                Divider()
                    .padding(.vertical, 4)
            }
        }
    }
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Metadata")
                .font(.system(size: 24, weight: .semibold))
            
            if let ratingKey = metadata.ratingKey {
                InfoRow(label: "Rating Key", value: ratingKey)
            }
            
            if let guid = metadata.guid {
                InfoRow(label: "GUID", value: guid)
            }
            
            if let type = metadata.type {
                InfoRow(label: "Type", value: type.capitalized)
            }
            
            if let year = metadata.year {
                InfoRow(label: "Year", value: "\(year)")
            }
            
            if let studio = metadata.studio {
                InfoRow(label: "Studio", value: studio)
            }
            
            if let contentRating = metadata.contentRating {
                InfoRow(label: "Content Rating", value: contentRating)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatBitrate(_ bitrate: Int) -> String {
        if bitrate >= 1000000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1000000.0)
        } else if bitrate >= 1000 {
            return String(format: "%.0f kbps", Double(bitrate) / 1000.0)
        } else {
            return "\(bitrate) bps"
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDuration(_ milliseconds: Int) -> String {
        let totalSeconds = milliseconds / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Info Row Component

struct InfoRow: View {
    let label: String
    let value: String
    var isFile: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            
            if isFile {
                Text(value)
                    .font(.system(size: 18, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            } else {
                Text(value)
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    let sampleMedia = PlexMedia(
        id: 1,
        duration: 7200000,
        bitrate: 15000000,
        width: 1920,
        height: 1080,
        aspectRatio: 1.78,
        audioChannels: 6,
        audioCodec: "ac3",
        videoCodec: "h264",
        videoResolution: "1080p",
        container: "mkv",
        videoFrameRate: "24p",
        Part: [
            PlexPart(
                id: 1,
                key: "/library/parts/1/file.mkv",
                duration: 7200000,
                file: "/path/to/movie.mkv",
                size: 8000000000,
                container: "mkv"
            )
        ]
    )
    
    let sampleMetadata = PlexMetadata(
        ratingKey: "123",
        type: "movie",
        title: "Sample Movie",
        year: 2024,
        Media: [sampleMedia]
    )
    
    VideoInfoOverlay(metadata: sampleMetadata, isPresented: .constant(true))
}

