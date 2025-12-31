//
//  TopShelfItem.swift
//  Rivulet
//
//  Lightweight model for Top Shelf extension data sharing
//

import Foundation

/// Minimal data structure for Top Shelf items
/// Shared between main app and TV Services Extension via App Groups
struct TopShelfItem: Codable, Sendable {
    let ratingKey: String
    let title: String
    let subtitle: String?        // Show name for episodes
    let imageURL: String         // Full Plex URL with token
    let progress: Double         // 0.0-1.0 watch progress
    let type: String             // "movie" or "episode"
    let lastWatched: Date
    let serverIdentifier: String // Server machine ID for deep link
}
