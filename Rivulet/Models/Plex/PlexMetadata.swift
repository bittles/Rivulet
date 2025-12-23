//
//  PlexMetadata.swift
//  Rivulet
//
//  Ported from plex_watchOS - Metadata.swift
//  Extended for video content (movies, TV shows, episodes)
//  Original created by Bain Gurley on 4/29/24.
//

import Foundation

// MARK: - Cast & Crew Models

/// Actor/cast member with role information
struct PlexRole: Codable, Identifiable, Sendable {
    var id: String { "\(tag ?? "")-\(role ?? "")" }
    var tag: String?        // Actor name
    var role: String?       // Character name
    var thumb: String?      // Photo URL
}

/// Director/Writer/Producer
struct PlexCrewMember: Codable, Identifiable, Sendable {
    var id: String { tag ?? UUID().uuidString }
    var tag: String?
    var thumb: String?
}

/// Trailer/Extra content
struct PlexExtra: Codable, Identifiable, Sendable {
    var id: String { ratingKey ?? UUID().uuidString }
    var ratingKey: String?
    var key: String?
    var type: String?
    var title: String?
    var subtype: String?    // "trailer", "behindTheScenes", etc.
    var thumb: String?
    var duration: Int?
    var extraType: Int?     // 1=trailer
}

/// Container for extras in Plex API response
struct PlexExtrasContainer: Codable, Sendable {
    var Metadata: [PlexExtra]?
}

// MARK: - Main Metadata Model

/// Plex media item metadata (movie, show, season, episode)
struct PlexMetadata: Codable, Identifiable, Hashable, Sendable {
    var id: String {
        return ratingKey ?? UUID().uuidString
    }

    // MARK: - Core Identifiers
    var ratingKey: String?
    var key: String?
    var guid: String?
    var type: String?             // "movie", "show", "season", "episode"

    // MARK: - Display Info
    var title: String?
    var originalTitle: String?
    var studio: String?
    var contentRating: String?    // "PG-13", "TV-MA", etc.
    var summary: String?
    var tagline: String?
    var year: Int?

    // MARK: - Ratings
    var rating: Double?
    var audienceRating: Double?
    var ratingImage: String?
    var audienceRatingImage: String?

    // MARK: - Artwork
    var thumb: String?
    var art: String?
    var banner: String?

    // MARK: - Timing
    var duration: Int?            // Milliseconds
    var originallyAvailableAt: String?
    var addedAt: Int?
    var updatedAt: Int?

    // MARK: - Library Context
    var librarySectionTitle: String?
    var librarySectionID: Int?
    var librarySectionKey: String?

    // MARK: - Parent Info (for episodes -> season)
    var parentRatingKey: String?
    var parentGuid: String?
    var parentKey: String?
    var parentTitle: String?
    var parentIndex: Int?         // Season number
    var parentThumb: String?

    // MARK: - Grandparent Info (for episodes -> show)
    var grandparentRatingKey: String?
    var grandparentGuid: String?
    var grandparentKey: String?
    var grandparentTitle: String?
    var grandparentThumb: String?
    var grandparentArt: String?
    var grandparentTheme: String?

    // MARK: - Episode/Season Specific
    var index: Int?               // Episode number in season
    var leafCount: Int?           // Total episodes (for shows/seasons)
    var viewedLeafCount: Int?     // Watched episodes
    var childCount: Int?          // Number of seasons (for shows)

    // MARK: - Watch Status
    var viewCount: Int?
    var viewOffset: Int?          // Resume position in milliseconds
    var lastViewedAt: Int?
    var skipCount: Int?

    // MARK: - User Rating
    var userRating: Double?
    var lastRatedAt: Int?

    // MARK: - Media Files
    var Media: [PlexMedia]?

    // MARK: - Cast & Crew
    var Role: [PlexRole]?
    var Director: [PlexCrewMember]?
    var Writer: [PlexCrewMember]?

    // MARK: - Extras (Trailers, etc.)
    var Extras: PlexExtrasContainer?

    // MARK: - Additional Metadata
    var hasPremiumPrimaryExtra: String?
    var primaryExtraKey: String?

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(ratingKey)
    }

    static func == (lhs: PlexMetadata, rhs: PlexMetadata) -> Bool {
        lhs.ratingKey == rhs.ratingKey
    }

    // MARK: - Convenience Init for Previews/Testing

    init(
        ratingKey: String? = nil,
        key: String? = nil,
        guid: String? = nil,
        type: String? = nil,
        title: String? = nil,
        originalTitle: String? = nil,
        studio: String? = nil,
        contentRating: String? = nil,
        summary: String? = nil,
        tagline: String? = nil,
        year: Int? = nil,
        rating: Double? = nil,
        audienceRating: Double? = nil,
        ratingImage: String? = nil,
        audienceRatingImage: String? = nil,
        thumb: String? = nil,
        art: String? = nil,
        banner: String? = nil,
        duration: Int? = nil,
        originallyAvailableAt: String? = nil,
        addedAt: Int? = nil,
        updatedAt: Int? = nil,
        librarySectionTitle: String? = nil,
        librarySectionID: Int? = nil,
        librarySectionKey: String? = nil,
        parentRatingKey: String? = nil,
        parentGuid: String? = nil,
        parentKey: String? = nil,
        parentTitle: String? = nil,
        parentIndex: Int? = nil,
        parentThumb: String? = nil,
        grandparentRatingKey: String? = nil,
        grandparentGuid: String? = nil,
        grandparentKey: String? = nil,
        grandparentTitle: String? = nil,
        grandparentThumb: String? = nil,
        grandparentArt: String? = nil,
        grandparentTheme: String? = nil,
        index: Int? = nil,
        leafCount: Int? = nil,
        viewedLeafCount: Int? = nil,
        childCount: Int? = nil,
        viewCount: Int? = nil,
        viewOffset: Int? = nil,
        lastViewedAt: Int? = nil,
        skipCount: Int? = nil,
        userRating: Double? = nil,
        lastRatedAt: Int? = nil,
        Media: [PlexMedia]? = nil,
        Role: [PlexRole]? = nil,
        Director: [PlexCrewMember]? = nil,
        Writer: [PlexCrewMember]? = nil,
        Extras: PlexExtrasContainer? = nil,
        hasPremiumPrimaryExtra: String? = nil,
        primaryExtraKey: String? = nil
    ) {
        self.ratingKey = ratingKey
        self.key = key
        self.guid = guid
        self.type = type
        self.title = title
        self.originalTitle = originalTitle
        self.studio = studio
        self.contentRating = contentRating
        self.summary = summary
        self.tagline = tagline
        self.year = year
        self.rating = rating
        self.audienceRating = audienceRating
        self.ratingImage = ratingImage
        self.audienceRatingImage = audienceRatingImage
        self.thumb = thumb
        self.art = art
        self.banner = banner
        self.duration = duration
        self.originallyAvailableAt = originallyAvailableAt
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.librarySectionTitle = librarySectionTitle
        self.librarySectionID = librarySectionID
        self.librarySectionKey = librarySectionKey
        self.parentRatingKey = parentRatingKey
        self.parentGuid = parentGuid
        self.parentKey = parentKey
        self.parentTitle = parentTitle
        self.parentIndex = parentIndex
        self.parentThumb = parentThumb
        self.grandparentRatingKey = grandparentRatingKey
        self.grandparentGuid = grandparentGuid
        self.grandparentKey = grandparentKey
        self.grandparentTitle = grandparentTitle
        self.grandparentThumb = grandparentThumb
        self.grandparentArt = grandparentArt
        self.grandparentTheme = grandparentTheme
        self.index = index
        self.leafCount = leafCount
        self.viewedLeafCount = viewedLeafCount
        self.childCount = childCount
        self.viewCount = viewCount
        self.viewOffset = viewOffset
        self.lastViewedAt = lastViewedAt
        self.skipCount = skipCount
        self.userRating = userRating
        self.lastRatedAt = lastRatedAt
        self.Media = Media
        self.Role = Role
        self.Director = Director
        self.Writer = Writer
        self.Extras = Extras
        self.hasPremiumPrimaryExtra = hasPremiumPrimaryExtra
        self.primaryExtraKey = primaryExtraKey
    }
}

// MARK: - Computed Properties

extension PlexMetadata {
    /// Duration formatted as "Xh Ym" or "Ym"
    var durationFormatted: String? {
        guard let durationMs = duration else { return nil }
        let totalMinutes = durationMs / 1000 / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Resume position formatted
    var viewOffsetFormatted: String? {
        guard let offset = viewOffset else { return nil }
        let totalMinutes = offset / 1000 / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Progress as percentage (0.0 - 1.0)
    var watchProgress: Double? {
        guard let offset = viewOffset, let total = duration, total > 0 else { return nil }
        return Double(offset) / Double(total)
    }

    /// Check if item has been partially watched
    var isInProgress: Bool {
        guard let progress = watchProgress else { return false }
        return progress > 0.02 && progress < 0.9
    }

    /// Check if item has been fully watched
    var isWatched: Bool {
        if let progress = watchProgress, progress >= 0.9 {
            return true
        }
        return (viewCount ?? 0) > 0
    }

    /// Episode string (e.g., "S01E05")
    var episodeString: String? {
        guard type == "episode" else { return nil }
        let season = parentIndex ?? 0
        let episode = index ?? 0
        return String(format: "S%02dE%02d", season, episode)
    }

    /// Full episode title (e.g., "S01E05 - Episode Title")
    var fullEpisodeTitle: String? {
        guard let epString = episodeString, let title = title else { return nil }
        return "\(epString) - \(title)"
    }

    /// Best thumbnail URL (falls back through parent/grandparent)
    var bestThumb: String? {
        thumb ?? parentThumb ?? grandparentThumb
    }

    /// Best art URL (falls back through parent/grandparent)
    var bestArt: String? {
        art ?? grandparentArt
    }

    /// Media type for display
    var mediaTypeDisplay: String {
        switch type {
        case "movie": return "Movie"
        case "show": return "TV Show"
        case "season": return "Season"
        case "episode": return "Episode"
        default: return type?.capitalized ?? "Unknown"
        }
    }

    /// First media file's streaming key
    var streamKey: String? {
        Media?.first?.Part?.first?.key
    }

    // MARK: - Cast & Crew Helpers

    /// All cast members
    var cast: [PlexRole] {
        Role ?? []
    }

    /// Primary director name
    var primaryDirector: String? {
        Director?.first?.tag
    }

    /// Primary writer name
    var primaryWriter: String? {
        Writer?.first?.tag
    }

    /// First trailer if available
    var trailer: PlexExtra? {
        Extras?.Metadata?.first { $0.extraType == 1 || $0.subtype == "trailer" }
    }

    /// All extras (trailers, behind the scenes, etc.)
    var allExtras: [PlexExtra] {
        Extras?.Metadata ?? []
    }
}
