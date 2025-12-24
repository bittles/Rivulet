//
//  MediaTrack.swift
//  Rivulet
//
//  Unified track model for audio and subtitle streams
//

import Foundation

/// Represents an audio or subtitle track from any player engine
struct MediaTrack: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let language: String?
    let languageCode: String?
    let codec: String?
    let isDefault: Bool
    let isForced: Bool
    let isHearingImpaired: Bool

    init(
        id: Int,
        name: String,
        language: String? = nil,
        languageCode: String? = nil,
        codec: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isHearingImpaired: Bool = false
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.languageCode = languageCode
        self.codec = codec
        self.isDefault = isDefault
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
    }

    /// Creates a MediaTrack from a PlexStream
    init(from stream: PlexStream) {
        self.id = stream.id
        self.name = stream.displayTitle ?? stream.title ?? stream.language ?? "Track \(stream.id)"
        self.language = stream.language
        self.languageCode = stream.languageCode
        self.codec = stream.codec
        self.isDefault = stream.default ?? false
        self.isForced = stream.forced ?? false
        self.isHearingImpaired = stream.hearingImpaired ?? false
    }

    /// Display name with additional info
    var displayName: String {
        var components: [String] = [name]

        if isForced {
            components.append("(Forced)")
        }
        if isHearingImpaired {
            components.append("(SDH)")
        }

        return components.joined(separator: " ")
    }
}
