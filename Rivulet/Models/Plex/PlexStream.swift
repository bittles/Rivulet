//
//  PlexStream.swift
//  Rivulet
//
//  Media stream information (video, audio, subtitle tracks)
//

import Foundation

/// Represents a media stream within a Plex media part
/// streamType: 1 = video, 2 = audio, 3 = subtitle
struct PlexStream: Codable, Identifiable, Sendable {
    let id: Int
    let streamType: Int
    let codec: String?
    let codecID: String?
    let language: String?
    let languageCode: String?
    let languageTag: String?
    let displayTitle: String?
    let title: String?
    let `default`: Bool?
    let forced: Bool?
    let selected: Bool?

    // Video-specific
    let bitDepth: Int?
    let chromaLocation: String?
    let chromaSubsampling: String?
    let colorPrimaries: String?
    let colorRange: String?
    let colorSpace: String?
    let colorTrc: String?
    let DOVIBLCompatID: Int?
    let DOVIBLPresent: Bool?
    let DOVIELPresent: Bool?
    let DOVILevel: Int?
    let DOVIPresent: Bool?
    let DOVIProfile: Int?
    let DOVIRPUPresent: Bool?
    let DOVIVersion: String?
    let frameRate: Double?
    let height: Int?
    let width: Int?
    let level: Int?
    let profile: String?
    let refFrames: Int?
    let scanType: String?

    // Audio-specific
    let audioChannelLayout: String?
    let channels: Int?
    let bitrate: Int?
    let samplingRate: Int?

    // Subtitle-specific
    let format: String?
    let key: String?           // For external subtitles
    let extendedDisplayTitle: String?
    let hearingImpaired: Bool?

    // MARK: - Convenience Properties

    var isVideo: Bool { streamType == 1 }
    var isAudio: Bool { streamType == 2 }
    var isSubtitle: Bool { streamType == 3 }

    /// Whether this is an HDR stream
    var isHDR: Bool {
        guard isVideo else { return false }
        // Check for HDR indicators
        if let colorTrc = colorTrc?.lowercased() {
            if colorTrc.contains("smpte2084") || colorTrc.contains("pq") ||
               colorTrc.contains("hlg") || colorTrc.contains("arib-std-b67") {
                return true
            }
        }
        if let colorSpace = colorSpace?.lowercased() {
            if colorSpace.contains("bt2020") {
                return true
            }
        }
        return false
    }

    /// Whether this is Dolby Vision
    var isDolbyVision: Bool {
        DOVIPresent == true || DOVIProfile != nil
    }

    /// Whether this subtitle format requires VLC for proper rendering
    var isAdvancedSubtitle: Bool {
        guard isSubtitle else { return false }
        let advancedFormats = ["ass", "ssa", "pgs", "pgssub", "dvdsub", "dvbsub", "vobsub", "hdmv_pgs_subtitle"]
        if let codec = codec?.lowercased() {
            return advancedFormats.contains(codec)
        }
        if let format = format?.lowercased() {
            return advancedFormats.contains(format)
        }
        return false
    }
}
