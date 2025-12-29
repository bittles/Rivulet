//
//  CastMemberCard.swift
//  Rivulet
//
//  Cast and crew member cards for detail view - matches MediaPosterCard style
//

import SwiftUI

// MARK: - Person Card

/// Card for cast/crew members - matches MediaPosterCard style
struct PersonCard: View {
    let name: String
    let subtitle: String?
    let thumbURL: URL?
    let serverURL: String
    let authToken: String

    #if os(tvOS)
    private let cardWidth: CGFloat = 160
    private let cardHeight: CGFloat = 240
    private let cornerRadius: CGFloat = 16
    private let nameFont: CGFloat = 19
    private let subtitleFont: CGFloat = 16
    #else
    private let cardWidth: CGFloat = 120
    private let cardHeight: CGFloat = 180
    private let cornerRadius: CGFloat = 12
    private let nameFont: CGFloat = 15
    private let subtitleFont: CGFloat = 13
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Photo - full card is the image
            personImage
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                #if os(tvOS)
                .hoverEffect(.highlight)
                // GPU-accelerated shadow: blur is hardware-accelerated, unlike .shadow() with large radius
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.black)
                        .blur(radius: 12)
                        .offset(y: 6)
                        .opacity(0.4)
                )
                .padding(.bottom, 10)  // Space for hover scale effect
                #endif

            // Name and role - below image like MediaPosterCard
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.system(size: nameFont, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: cardWidth, alignment: .leading)

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: subtitleFont, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: cardWidth, alignment: .leading)
                }
            }
            #if os(tvOS)
            .frame(height: 52, alignment: .top)
            #else
            .frame(height: 44, alignment: .top)
            #endif
        }
    }

    // MARK: - Person Image

    private var personImage: some View {
        CachedAsyncImage(url: fullThumbURL) { phase in
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
                        Image(systemName: "person.fill")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }
        }
    }

    private var fullThumbURL: URL? {
        guard let thumbPath = thumbURL?.absoluteString else { return nil }
        if thumbPath.hasPrefix("http") {
            return thumbURL
        }
        var urlString = "\(serverURL)\(thumbPath)"
        if !urlString.contains("X-Plex-Token") {
            urlString += urlString.contains("?") ? "&" : "?"
            urlString += "X-Plex-Token=\(authToken)"
        }
        return URL(string: urlString)
    }
}

// MARK: - Cast & Crew Row

/// Horizontal scrolling row of cast and crew members
struct CastCrewRow: View {
    let cast: [PlexRole]
    let directors: [PlexCrewMember]
    let serverURL: String
    let authToken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cast & Crew")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 48)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    // Directors first
                    ForEach(directors) { director in
                        Button { } label: {
                            PersonCard(
                                name: director.tag ?? "Unknown",
                                subtitle: "Director",
                                thumbURL: director.thumb.flatMap { URL(string: $0) },
                                serverURL: serverURL,
                                authToken: authToken
                            )
                        }
                        #if os(tvOS)
                        .buttonStyle(CardButtonStyle())
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }

                    // Cast members
                    ForEach(cast) { actor in
                        Button { } label: {
                            PersonCard(
                                name: actor.tag ?? "Unknown",
                                subtitle: actor.role,
                                thumbURL: actor.thumb.flatMap { URL(string: $0) },
                                serverURL: serverURL,
                                authToken: authToken
                            )
                        }
                        #if os(tvOS)
                        .buttonStyle(CardButtonStyle())
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        PersonCard(
            name: "Bryan Cranston",
            subtitle: "Walter White",
            thumbURL: nil,
            serverURL: "http://localhost:32400",
            authToken: "test"
        )
    }
}
