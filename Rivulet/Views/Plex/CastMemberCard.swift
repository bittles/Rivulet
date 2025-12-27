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
    var isDirector: Bool = false

    #if os(tvOS)
    private let cardWidth: CGFloat = 160
    private let cardHeight: CGFloat = 240
    private let cornerRadius: CGFloat = 16
    private let nameFont: CGFloat = 19
    private let subtitleFont: CGFloat = 16
    private let badgeSize: CGFloat = 36
    #else
    private let cardWidth: CGFloat = 120
    private let cardHeight: CGFloat = 180
    private let cornerRadius: CGFloat = 12
    private let nameFont: CGFloat = 15
    private let subtitleFont: CGFloat = 13
    private let badgeSize: CGFloat = 24
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Photo - full card is the image
            ZStack(alignment: .topTrailing) {
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
                    #endif

                // Director badge
                if isDirector {
                    ZStack {
                        Circle()
                            .fill(.orange.gradient)
                            .frame(width: badgeSize, height: badgeSize)

                        Image(systemName: "megaphone.fill")
                            .font(.system(size: badgeSize * 0.5, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(10)
                }
            }
            #if os(tvOS)
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
    let writers: [PlexCrewMember]
    let serverURL: String
    let authToken: String

    // Use @FocusState instead of prefersDefaultFocus (which is broken in ScrollView)
    @FocusState private var focusedPersonId: String?

    /// Get the ID of the first person (for default focus)
    private var firstPersonId: String? {
        if let firstDirector = directors.first {
            return firstDirector.id
        } else if let firstActor = cast.first {
            return firstActor.id
        } else if let firstWriter = writers.first {
            return firstWriter.id
        }
        return nil
    }

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
                                authToken: authToken,
                                isDirector: true
                            )
                        }
                        #if os(tvOS)
                        .buttonStyle(CardButtonStyle())
                        .focused($focusedPersonId, equals: director.id)
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
                        .focused($focusedPersonId, equals: actor.id)
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }

                    // Writers (if not already a director)
                    ForEach(writers) { writer in
                        let isDirector = directors.contains { $0.tag == writer.tag }
                        if !isDirector {
                            Button { } label: {
                                PersonCard(
                                    name: writer.tag ?? "Unknown",
                                    subtitle: "Writer",
                                    thumbURL: writer.thumb.flatMap { URL(string: $0) },
                                    serverURL: serverURL,
                                    authToken: authToken
                                )
                            }
                            #if os(tvOS)
                            .buttonStyle(CardButtonStyle())
                            .focused($focusedPersonId, equals: writer.id)
                            #else
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
            }
            .scrollClipDisabled()
        }
        .focusSection()
        #if os(tvOS)
        // defaultFocus sets which item receives focus when this section becomes focused
        .defaultFocus($focusedPersonId, firstPersonId)
        #endif
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
            authToken: "test",
            isDirector: true
        )
    }
}
