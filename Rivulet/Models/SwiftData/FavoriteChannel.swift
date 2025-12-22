//
//  FavoriteChannel.swift
//  Rivulet
//
//  Created by Bain Gurley on 11/28/25.
//

import Foundation
import SwiftData

/// Tracks favorite channels with ordering
@Model
final class FavoriteChannel {
    @Attribute(.unique) var id: UUID
    var sortOrder: Int
    var addedAt: Date

    var channel: Channel?

    init(sortOrder: Int = 0) {
        self.id = UUID()
        self.sortOrder = sortOrder
        self.addedAt = Date()
    }
}
