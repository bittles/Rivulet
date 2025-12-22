//
//  MediaPosterCard.swift
//  Rivulet
//
//  Reusable poster card component for movies, shows, and episodes
//

import SwiftUI

struct MediaPosterCard: View {
    let item: PlexMetadata
    let serverURL: String
    let authToken: String

    @Environment(\.isFocused) private var isFocused

    #if os(tvOS)
    private let posterWidth: CGFloat = 220
    private let posterHeight: CGFloat = 330
    private let cornerRadius: CGFloat = 16
    #else
    private let posterWidth: CGFloat = 180
    private let posterHeight: CGFloat = 270
    private let cornerRadius: CGFloat = 12
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Poster Image
            posterImage
                .frame(width: posterWidth, height: posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(alignment: .bottom) {
                    progressOverlay
                }
                .overlay(alignment: .topTrailing) {
                    unwatchedBadge
                }
                #if os(tvOS)
                .shadow(
                    color: .black.opacity(isFocused ? 0.5 : 0.3),
                    radius: isFocused ? 30 : 10,
                    y: isFocused ? 15 : 5
                )
                .scaleEffect(isFocused ? 1.08 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFocused)
                #endif

            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "Unknown")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isFocused ? .white : .white.opacity(0.85))
                    .lineLimit(2)
                    .frame(width: posterWidth, alignment: .leading)

                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            #if os(tvOS)
            .opacity(isFocused ? 1.0 : 0.8)
            .animation(.easeOut(duration: 0.2), value: isFocused)
            #endif
        }
    }

    // MARK: - Poster Image

    private var posterImage: some View {
        AsyncImage(url: posterURL) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color(white: 0.15))
                    .overlay {
                        ProgressView()
                            .tint(.white.opacity(0.3))
                    }
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.18), Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        Image(systemName: iconForType)
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))
                    }
            @unknown default:
                Rectangle()
                    .fill(Color(white: 0.15))
            }
        }
    }

    // MARK: - Progress Overlay

    @ViewBuilder
    private var progressOverlay: some View {
        if let progress = item.watchProgress, progress > 0 && progress < 1 {
            VStack {
                Spacer()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Rectangle()
                            .fill(.black.opacity(0.6))

                        // Progress
                        Rectangle()
                            .fill(.white)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    // MARK: - Unwatched Badge

    @ViewBuilder
    private var unwatchedBadge: some View {
        if item.viewCount == nil || item.viewCount == 0 {
            if let leafCount = item.leafCount, leafCount > 0 {
                Text("\(leafCount)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.blue)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    )
                    .padding(10)
            }
        }
    }

    // MARK: - Computed Properties

    private var posterURL: URL? {
        guard let thumb = item.thumb else { return nil }
        var urlString = "\(serverURL)\(thumb)"
        if !urlString.contains("X-Plex-Token") {
            urlString += urlString.contains("?") ? "&" : "?"
            urlString += "X-Plex-Token=\(authToken)"
        }
        return URL(string: urlString)
    }

    private var iconForType: String {
        switch item.type {
        case "movie": return "film"
        case "show": return "tv"
        case "season": return "number.square"
        case "episode": return "play.rectangle"
        default: return "photo"
        }
    }

    private var subtitleText: String? {
        switch item.type {
        case "movie":
            return item.year.map { String($0) }
        case "show":
            if let year = item.year {
                return String(year)
            }
            return nil
        case "episode":
            return item.episodeString
        case "season":
            return item.title
        default:
            return nil
        }
    }
}

// MARK: - Horizontal Scroll Row

struct MediaRow: View {
    let title: String
    let items: [PlexMetadata]
    let serverURL: String
    let authToken: String
    var onItemSelected: ((PlexMetadata) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 48)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(items, id: \.ratingKey) { item in
                        Button {
                            onItemSelected?(item)
                        } label: {
                            MediaPosterCard(
                                item: item,
                                serverURL: serverURL,
                                authToken: authToken
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 48)
            }
        }
    }
}

// MARK: - Vertical Grid

struct MediaGrid: View {
    let items: [PlexMetadata]
    let serverURL: String
    let authToken: String
    var onItemSelected: ((PlexMetadata) -> Void)?

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 24)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 32) {
            ForEach(items, id: \.ratingKey) { item in
                Button {
                    onItemSelected?(item)
                } label: {
                    MediaPosterCard(
                        item: item,
                        serverURL: serverURL,
                        authToken: authToken
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 48)
    }
}

#Preview {
    let sampleItem = PlexMetadata(
        ratingKey: "123",
        key: "/library/metadata/123",
        type: "movie",
        title: "Sample Movie",
        year: 2024
    )

    MediaPosterCard(
        item: sampleItem,
        serverURL: "http://localhost:32400",
        authToken: "test"
    )
}
