//
//  MPVPlayerDelegate.swift
//  Rivulet
//
//  Delegate protocol for MPV player events
//

import Foundation

@MainActor
protocol MPVPlayerDelegate: AnyObject {
    func mpvPlayerDidChangeState(_ state: MPVPlayerState)
    func mpvPlayerTimeDidChange(current: Double, duration: Double)
    func mpvPlayerDidUpdateTracks(audio: [MPVTrack], subtitles: [MPVTrack])
    func mpvPlayerDidEncounterError(_ message: String)
}

/// MPV playback state
enum MPVPlayerState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case ended
    case error(String)
}

/// Represents a media track (audio or subtitle)
struct MPVTrack: Identifiable, Equatable, Sendable {
    let id: Int
    let type: TrackType
    let title: String?
    let language: String?
    let codec: String?
    let isDefault: Bool
    let isForced: Bool
    let isSelected: Bool

    // Audio-specific
    let channels: Int?
    let sampleRate: Int?

    enum TrackType: String, Sendable {
        case audio
        case subtitle
        case video
    }

    var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        if let lang = language {
            return lang
        }
        return "\(type.rawValue.capitalized) Track \(id)"
    }
}
