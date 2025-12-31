//
//  ContentProvider.swift
//  TopShelfExtension
//
//  TV Services Extension for Top Shelf content
//

import TVServices
import os.log

private let logger = Logger(subsystem: "com.gstudios.rivulet.TopShelfExtension", category: "ContentProvider")

class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> TVTopShelfContent? {
        logger.info("TopShelf: loadTopShelfContent called")

        let items = TopShelfCache.shared.readItems()
        logger.info("TopShelf: Read \(items.count) items from cache")

        guard !items.isEmpty else {
            logger.warning("TopShelf: No items to display, returning nil")
            return nil
        }

        let topShelfItems = items.compactMap { item -> TVTopShelfSectionedItem? in
            let tvItem = TVTopShelfSectionedItem(identifier: item.ratingKey)

            // Episode name or movie title
            tvItem.title = item.title

            // Use poster shape for tall artwork
            tvItem.imageShape = .poster

            // Set image from Plex URL (includes auth token)
            if let url = URL(string: item.imageURL) {
                tvItem.setImageURL(url, for: .screenScale1x)
                tvItem.setImageURL(url, for: .screenScale2x)
            }

            // Deep link to resume playback
            var components = URLComponents()
            components.scheme = "rivulet"
            components.host = "play"
            components.queryItems = [
                URLQueryItem(name: "ratingKey", value: item.ratingKey),
                URLQueryItem(name: "server", value: item.serverIdentifier)
            ]

            guard let actionURL = components.url else { return nil }

            tvItem.playAction = TVTopShelfAction(url: actionURL)
            tvItem.displayAction = tvItem.playAction

            return tvItem
        }

        guard !topShelfItems.isEmpty else {
            logger.warning("TopShelf: No valid items after mapping, returning nil")
            return nil
        }

        let section = TVTopShelfItemCollection(items: topShelfItems)
        section.title = "Continue Watching"

        logger.info("TopShelf: Returning \(topShelfItems.count) items in Continue Watching section")
        return TVTopShelfSectionedContent(sections: [section])
    }
}
