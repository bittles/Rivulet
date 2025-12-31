//
//  MPVProperty.swift
//  Rivulet
//
//  MPV property name constants
//

import Foundation

struct MPVProperty {
    // Video parameters
    static let videoParamsColormatrix = "video-params/colormatrix"
    static let videoParamsColorlevels = "video-params/colorlevels"
    static let videoParamsPrimaries = "video-params/primaries"
    static let videoParamsGamma = "video-params/gamma"
    static let videoParamsSigPeak = "video-params/sig-peak"
    static let videoParamsSceneMaxR = "video-params/scene-max-r"
    static let videoParamsSceneMaxG = "video-params/scene-max-g"
    static let videoParamsSceneMaxB = "video-params/scene-max-b"

    // Playback state
    static let pause = "pause"
    static let pausedForCache = "paused-for-cache"
    static let coreIdle = "core-idle"
    static let eofReached = "eof-reached"
    static let seeking = "seeking"

    // Time
    static let timePos = "time-pos"
    static let duration = "duration"
    static let percentPos = "percent-pos"

    // Tracks
    static let trackList = "track-list"
    static let trackListCount = "track-list/count"
    static let aid = "aid"           // Audio track ID
    static let sid = "sid"           // Subtitle track ID
    static let vid = "vid"           // Video track ID

    // Speed
    static let speed = "speed"

    // Volume
    static let volume = "volume"
    static let mute = "mute"

    // Cache (for live stream monitoring)
    static let demuxerCacheTime = "demuxer-cache-time"
    static let demuxerCacheDuration = "demuxer-cache-duration"
    static let demuxerCacheState = "demuxer-cache-state"
    static let playbackTime = "playback-time"
}
