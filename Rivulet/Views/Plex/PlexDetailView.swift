//
//  PlexDetailView.swift
//  Rivulet
//
//  Detail view for movies and TV shows with playback options
//

import SwiftUI

struct PlexDetailView: View {
    let item: PlexMetadata
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = PlexAuthManager.shared
    @State private var seasons: [PlexMetadata] = []
    @State private var selectedSeason: PlexMetadata?
    @State private var episodes: [PlexMetadata] = []
    @State private var isLoadingSeasons = false
    @State private var isLoadingEpisodes = false
    @State private var showPlayer = false
    @State private var selectedEpisode: PlexMetadata?

    // Music album state
    @State private var tracks: [PlexMetadata] = []
    @State private var isLoadingTracks = false
    @State private var selectedTrack: PlexMetadata?

    // Music artist state
    @State private var albums: [PlexMetadata] = []
    @State private var isLoadingAlbums = false
    @State private var navigateToAlbum: PlexMetadata?  // For binding-based navigation

    // New state for cast/crew and related items
    @State private var fullMetadata: PlexMetadata?
    @State private var relatedItems: [PlexMetadata] = []
    @State private var isWatched = false
    @State private var isStarred = false  // For music: 5-star rating toggle
    @State private var isLoadingExtras = false
    @State private var showTrailerPlayer = false

    private let networkManager = PlexNetworkManager.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero Section with backdrop
                heroSection

                // Content Section
                VStack(alignment: .leading, spacing: 24) {
                    // Title and metadata
                    headerSection

                    // Action buttons
                    actionButtons

                    // Summary
                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    // TV Show specific: Seasons and Episodes
                    if item.type == "show" {
                        seasonSection
                    }

                    // Album specific: Tracks
                    if item.type == "album" {
                        trackSection
                    }

                    // Artist specific: Albums
                    if item.type == "artist" {
                        albumSection
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 24)

                // Cast & Crew Section
                if let metadata = fullMetadata,
                   (!metadata.cast.isEmpty || !(metadata.Director?.isEmpty ?? true)) {
                    CastCrewRow(
                        cast: metadata.cast,
                        directors: metadata.Director ?? [],
                        writers: metadata.Writer ?? [],
                        serverURL: authManager.selectedServerURL ?? "",
                        authToken: authManager.authToken ?? ""
                    )
                    .padding(.top, 32)
                }

                // Related Items Section
                if !relatedItems.isEmpty {
                    relatedItemsSection
                        .padding(.top, 32)
                }

                Spacer()
                    .frame(height: 60)
            }
        }
        .ignoresSafeArea(edges: .top)
        .task {
            // Debug: log what item we're loading
            print("📋 PlexDetailView loading: \(item.title ?? "?") (type: \(item.type ?? "nil"), ratingKey: \(item.ratingKey ?? "nil"))")

            // Initialize watched state
            isWatched = item.isWatched

            // Initialize starred state for music (userRating > 0 means starred)
            isStarred = (item.userRating ?? 0) > 0

            // Load full metadata for cast/crew and trailer
            await loadFullMetadata()

            // Load related items
            await loadRelatedItems()

            // Load seasons for TV shows
            if item.type == "show" {
                await loadSeasons()
            }

            // Load tracks for albums
            if item.type == "album" {
                await loadTracks()
            }

            // Load albums for artists
            if item.type == "artist" {
                await loadAlbums()
            }
        }
        #if os(tvOS)
        .onChange(of: showPlayer) { _, shouldShow in
            if shouldShow {
                presentPlayer()
            }
        }
        #else
        .fullScreenCover(isPresented: $showPlayer) {
            // Play the selected episode/track if available, otherwise play the main item (movie/album)
            let playItem = selectedEpisode ?? selectedTrack ?? item
            let resumeOffset = Double(playItem.viewOffset ?? 0) / 1000.0
            UniversalPlayerView(
                metadata: playItem,
                startOffset: resumeOffset > 0 ? resumeOffset : nil
            )
        }
        #endif
        .fullScreenCover(isPresented: $showTrailerPlayer) {
            // Play trailer if available
            if let trailer = fullMetadata?.trailer {
                TrailerPlayerView(
                    trailer: trailer,
                    serverURL: authManager.selectedServerURL ?? "",
                    authToken: authManager.authToken ?? ""
                )
            }
        }
        .onChange(of: showPlayer) { _, isShowing in
            // Clear selected episode/track when player closes
            if !isShowing {
                selectedEpisode = nil
                selectedTrack = nil
            }
        }
        .navigationDestination(item: $navigateToAlbum) { album in
            PlexDetailView(item: album)
        }
        #if os(tvOS)
        // Intercept exit command when viewing nested album to prevent going all the way back
        .onExitCommand {
            if navigateToAlbum != nil {
                navigateToAlbum = nil
            }
        }
        #endif
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Background art with squircle corners
            CachedAsyncImage(url: artURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .frame(height: 600)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay {
                // Gradient overlay for text readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            // GPU-accelerated shadow: blur is hardware-accelerated, unlike .shadow() with large radius
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.black)
                    .blur(radius: 20)
                    .offset(y: 10)
                    .opacity(0.5)
            )
            .padding(.horizontal, 48)

            // Poster overlay - larger with squircle corners
            HStack(alignment: .bottom, spacing: 32) {
                CachedAsyncImage(url: posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty:
                        Rectangle()
                            .fill(Color(white: 0.15))
                            .overlay { ProgressView().tint(.white.opacity(0.3)) }
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
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                    }
                }
                .frame(width: 200, height: isMusicItem ? 200 : 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                // GPU-accelerated shadow
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.black)
                        .blur(radius: 16)
                        .offset(y: 8)
                        .opacity(0.5)
                )

                Spacer()
            }
            .padding(.horizontal, 96) // Inset from hero edges
            .padding(.bottom, isMusicItem ? -10 : -50) // Less overlap for square posters
        }
    }

    /// Check if this is a music item (album, artist, track)
    private var isMusicItem: Bool {
        item.type == "album" || item.type == "artist" || item.type == "track"
    }

    /// Icon for fallback poster based on item type
    private var iconForType: String {
        switch item.type {
        case "movie": return "film"
        case "show": return "tv"
        case "album": return "music.note.list"
        case "artist": return "music.mic"
        case "track": return "music.note"
        default: return "photo"
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Spacer for poster overlap (less for square music posters)
            Spacer()
                .frame(height: isMusicItem ? 20 : 60)

            Text(item.title ?? "Unknown Title")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                if let year = item.year {
                    Text(String(year))
                }

                if let contentRating = item.contentRating {
                    Text(contentRating)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                        }
                }

                if let duration = item.durationFormatted {
                    Text(duration)
                }

                if let rating = item.rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating))
                    }
                }

                // Show director if available
                if let director = fullMetadata?.primaryDirector {
                    HStack(spacing: 4) {
                        Image(systemName: "megaphone.fill")
                            .foregroundStyle(.orange)
                        Text(director)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let tagline = item.tagline {
                Text(tagline)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Play button - show for all playable items except artists
            // For albums: plays the first track
            if item.type != "artist" {
                Button {
                    if item.type == "album" {
                        // Play first track of album
                        if let firstTrack = tracks.first {
                            selectedTrack = firstTrack
                        }
                    }
                    showPlayer = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text(item.type == "album" ? "Play Album" : (item.isInProgress ? "Resume" : "Play"))
                    }
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(item.type == "album" && tracks.isEmpty)
            }

            // For music: Star rating toggle (5 stars or no rating)
            // For other content: Watched toggle button
            if isMusicItem {
                Button {
                    Task {
                        await toggleStarRating()
                    }
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(isStarred ? .yellow : .secondary)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task {
                        await toggleWatched()
                    }
                } label: {
                    Image(systemName: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(isWatched ? .green : .secondary)
                }
                .buttonStyle(.bordered)
            }

            // Trailer button (only show if available, not for music)
            if !isMusicItem, fullMetadata?.trailer != nil {
                Button {
                    showTrailerPlayer = true
                } label: {
                    Image(systemName: "film")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // Progress info on the right (not for music)
            if !isMusicItem, let progress = item.viewOffsetFormatted, item.isInProgress {
                Text("\(progress) watched")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Season Section (TV Shows)

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isLoadingSeasons {
                ProgressView("Loading seasons...")
            } else if !seasons.isEmpty {
                // Season picker
                Text("Seasons")
                    .font(.title2)
                    .fontWeight(.bold)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(seasons, id: \.ratingKey) { season in
                            Button {
                                selectedSeason = season
                                Task {
                                    await loadEpisodes(for: season)
                                }
                            } label: {
                                VStack {
                                    Text(season.title ?? "Season \(season.index ?? 0)")
                                        .font(.headline)
                                    if let leafCount = season.leafCount {
                                        Text("\(leafCount) episodes")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedSeason?.ratingKey == season.ratingKey ?
                                              Color.blue : Color.secondary.opacity(0.2))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Episodes list
                if isLoadingEpisodes {
                    ProgressView("Loading episodes...")
                        .padding(.top, 20)
                } else if !episodes.isEmpty {
                    Text("Episodes")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top, 16)

                    LazyVStack(spacing: 16) {
                        ForEach(episodes, id: \.ratingKey) { episode in
                            EpisodeRow(
                                episode: episode,
                                serverURL: authManager.selectedServerURL ?? "",
                                authToken: authManager.authToken ?? ""
                            ) {
                                // Play episode
                                selectedEpisode = episode
                                showPlayer = true
                            }
                        }
                    }
                    #if os(tvOS)
                    .padding(.horizontal, 8)  // Room for focus scale effect
                    #endif
                }
            }
        }
    }

    // MARK: - Track Section (Albums)

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isLoadingTracks {
                ProgressView("Loading tracks...")
            } else if !tracks.isEmpty {
                Text("Tracks")
                    .font(.title2)
                    .fontWeight(.bold)

                LazyVStack(spacing: 12) {
                    ForEach(Array(tracks.enumerated()), id: \.element.ratingKey) { index, track in
                        AlbumTrackRow(
                            track: track,
                            trackNumber: track.index ?? (index + 1),
                            serverURL: authManager.selectedServerURL ?? "",
                            authToken: authManager.authToken ?? ""
                        ) {
                            // Play track
                            selectedTrack = track
                            showPlayer = true
                        }
                    }
                }
                #if os(tvOS)
                .padding(.horizontal, 8)  // Room for focus scale effect
                #endif
            }
        }
    }

    // MARK: - Album Section (Artists)

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isLoadingAlbums {
                ProgressView("Loading albums...")
            } else if !albums.isEmpty {
                Text("Albums")
                    .font(.title2)
                    .fontWeight(.bold)

                LazyVStack(spacing: 16) {
                    ForEach(albums, id: \.ratingKey) { album in
                        Button {
                            navigateToAlbum = album
                        } label: {
                            ArtistAlbumRow(
                                album: album,
                                serverURL: authManager.selectedServerURL ?? "",
                                authToken: authManager.authToken ?? ""
                            )
                        }
                        #if os(tvOS)
                        .buttonStyle(CardButtonStyle())
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                #if os(tvOS)
                .padding(.horizontal, 8)  // Room for focus scale effect
                #endif
            }
        }
    }

    // MARK: - Related Items Section

    private var relatedItemsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("More Like This")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 48)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(relatedItems, id: \.ratingKey) { relatedItem in
                        NavigationLink(value: relatedItem) {
                            MediaPosterCard(
                                item: relatedItem,
                                serverURL: authManager.selectedServerURL ?? "",
                                authToken: authManager.authToken ?? ""
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Player Presentation (tvOS)

    #if os(tvOS)
    /// Present player using UIViewController to intercept Menu button
    private func presentPlayer() {
        let playItem = selectedEpisode ?? selectedTrack ?? item
        let resumeOffset = Double(playItem.viewOffset ?? 0) / 1000.0

        // Create viewModel first so we can pass the same instance to both view and container
        let viewModel = UniversalPlayerViewModel(
            metadata: playItem,
            serverURL: authManager.selectedServerURL ?? "",
            authToken: authManager.authToken ?? "",
            startOffset: resumeOffset > 0 ? resumeOffset : nil
        )

        // Create view with the external viewModel
        let playerView = UniversalPlayerView(viewModel: viewModel)

        // Create container that intercepts Menu button, passing the same viewModel
        let container = PlayerContainerViewController(
            rootView: playerView,
            viewModel: viewModel
        )

        // Update SwiftUI state when player is dismissed
        container.onDismiss = {
            showPlayer = false
        }

        // Present from top-most view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(container, animated: true)
        }
    }
    #endif

    // MARK: - Data Loading

    private func loadFullMetadata() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken,
              let ratingKey = item.ratingKey else { return }

        isLoadingExtras = true

        do {
            let metadata = try await networkManager.getFullMetadata(
                serverURL: serverURL,
                authToken: token,
                ratingKey: ratingKey
            )
            fullMetadata = metadata
        } catch {
            print("Failed to load full metadata: \(error)")
        }

        isLoadingExtras = false
    }

    private func loadRelatedItems() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken,
              let ratingKey = item.ratingKey else { return }

        do {
            let related = try await networkManager.getRelatedItems(
                serverURL: serverURL,
                authToken: token,
                ratingKey: ratingKey,
                limit: 12
            )
            relatedItems = related
        } catch {
            print("Failed to load related items: \(error)")
        }
    }

    private func toggleWatched() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken,
              let ratingKey = item.ratingKey else { return }

        do {
            if isWatched {
                try await networkManager.markUnwatched(
                    serverURL: serverURL,
                    authToken: token,
                    ratingKey: ratingKey
                )
            } else {
                try await networkManager.markWatched(
                    serverURL: serverURL,
                    authToken: token,
                    ratingKey: ratingKey
                )
            }
            isWatched.toggle()
        } catch {
            print("Failed to toggle watched status: \(error)")
        }
    }

    private func toggleStarRating() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken,
              let ratingKey = item.ratingKey else { return }

        do {
            // Toggle between 5 stars (rating=10) and no rating (rating=nil)
            let newRating: Int? = isStarred ? nil : 10
            try await networkManager.setRating(
                serverURL: serverURL,
                authToken: token,
                ratingKey: ratingKey,
                rating: newRating
            )
            isStarred.toggle()
        } catch {
            print("Failed to toggle star rating: \(error)")
        }
    }

    private func loadSeasons() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken,
              let ratingKey = item.ratingKey else { return }

        isLoadingSeasons = true

        do {
            let fetchedSeasons = try await networkManager.getChildren(
                serverURL: serverURL,
                authToken: token,
                ratingKey: ratingKey
            )
            seasons = fetchedSeasons

            // Auto-select first season
            if let first = fetchedSeasons.first {
                selectedSeason = first
                await loadEpisodes(for: first)
            }
        } catch {
            print("Failed to load seasons: \(error)")
        }

        isLoadingSeasons = false
    }

    private func loadEpisodes(for season: PlexMetadata) async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken,
              let ratingKey = season.ratingKey else { return }

        isLoadingEpisodes = true

        do {
            let fetchedEpisodes = try await networkManager.getChildren(
                serverURL: serverURL,
                authToken: token,
                ratingKey: ratingKey
            )
            episodes = fetchedEpisodes
        } catch {
            print("Failed to load episodes: \(error)")
        }

        isLoadingEpisodes = false
    }

    private func loadTracks() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken,
              let ratingKey = item.ratingKey else { return }

        isLoadingTracks = true

        do {
            let fetchedTracks = try await networkManager.getChildren(
                serverURL: serverURL,
                authToken: token,
                ratingKey: ratingKey
            )
            tracks = fetchedTracks
        } catch {
            print("Failed to load tracks: \(error)")
        }

        isLoadingTracks = false
    }

    private func loadAlbums() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken,
              let ratingKey = item.ratingKey else {
            print("🎵 Missing required data for loading albums")
            return
        }

        // Get librarySectionID from fullMetadata (fetched first) or item
        guard let librarySectionId = fullMetadata?.librarySectionID ?? item.librarySectionID else {
            print("🎵 Missing librarySectionID for artist - item: \(item.librarySectionID ?? -1), fullMetadata: \(fullMetadata?.librarySectionID ?? -1)")
            return
        }

        isLoadingAlbums = true

        do {
            // Use the library section endpoint with artist.id filter
            // This is more reliable than /children endpoint
            let fetchedAlbums = try await networkManager.getAlbumsForArtist(
                serverURL: serverURL,
                authToken: token,
                librarySectionId: librarySectionId,
                artistId: ratingKey
            )

            // Sort by year (newest first)
            albums = fetchedAlbums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }

            print("🎵 Found \(albums.count) albums for \(item.title ?? "?")")
            for album in albums.prefix(5) {
                print("  - \(album.title ?? "?") (type: \(album.type ?? "nil"), ratingKey: \(album.ratingKey ?? "nil"), parentKey: \(album.parentRatingKey ?? "nil"))")
            }
            if albums.count > 5 {
                print("  ... and \(albums.count - 5) more")
            }
        } catch {
            print("🎵 Failed to load albums: \(error)")
        }

        isLoadingAlbums = false
    }


    // MARK: - URL Helpers

    private var artURL: URL? {
        guard let art = item.bestArt,
              let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return nil }
        return URL(string: "\(serverURL)\(art)?X-Plex-Token=\(token)")
    }

    /// Poster URL - uses grandparent poster for episodes (series poster)
    private var posterURL: URL? {
        let thumb: String?

        // For TV show episodes, prefer the series poster (grandparentThumb)
        if item.type == "episode" || item.type == "season" {
            thumb = item.grandparentThumb ?? item.parentThumb ?? item.thumb
        } else {
            thumb = item.thumb
        }

        guard let thumbPath = thumb,
              let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return nil }
        return URL(string: "\(serverURL)\(thumbPath)?X-Plex-Token=\(token)")
    }

    private var thumbURL: URL? {
        guard let thumb = item.thumb,
              let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(token)")
    }
}

// MARK: - Episode Row

struct EpisodeRow: View {
    let episode: PlexMetadata
    let serverURL: String
    let authToken: String
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 16) {
                // Thumbnail
                CachedAsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay {
                                Image(systemName: "play.rectangle")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 200, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottom) {
                    // Progress bar
                    if let progress = episode.watchProgress, progress > 0 && progress < 1 {
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(height: 3)
                                    Rectangle()
                                        .fill(Color.blue)
                                        .frame(width: geo.size.width * progress, height: 3)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let epString = episode.episodeString {
                        Text(epString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(episode.title ?? "Episode")
                        .font(.headline)
                        .lineLimit(1)

                    if let duration = episode.durationFormatted {
                        Text(duration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let summary = episode.summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Watched indicator
                if episode.isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private var thumbURL: URL? {
        guard let thumb = episode.thumb else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(authToken)")
    }
}

// MARK: - Album Track Row

struct AlbumTrackRow: View {
    let track: PlexMetadata
    let trackNumber: Int
    let serverURL: String
    let authToken: String
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 16) {
                // Track number
                Text("\(trackNumber)")
                    #if os(tvOS)
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    #else
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    #endif
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title ?? "Track \(trackNumber)")
                        #if os(tvOS)
                        .font(.system(size: 22, weight: .medium))
                        #else
                        .font(.headline)
                        #endif
                        .lineLimit(1)

                    if let duration = track.durationFormatted {
                        Text(duration)
                            #if os(tvOS)
                            .font(.system(size: 18))
                            #else
                            .font(.caption)
                            #endif
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Play icon
                Image(systemName: "play.fill")
                    #if os(tvOS)
                    .font(.system(size: 20))
                    #endif
                    .foregroundStyle(.secondary)
            }
            #if os(tvOS)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            #else
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            #endif
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
            )
            #if os(tvOS)
            .hoverEffect(.highlight)
            #endif
        }
        #if os(tvOS)
        .buttonStyle(CardButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
    }
}

// MARK: - Artist Album Row

struct ArtistAlbumRow: View {
    let album: PlexMetadata
    let serverURL: String
    let authToken: String

    var body: some View {
        HStack(spacing: 16) {
            // Album artwork (square)
            CachedAsyncImage(url: thumbURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty:
                    Rectangle()
                        .fill(Color(white: 0.15))
                        .overlay { ProgressView().tint(.white.opacity(0.3)) }
                case .failure:
                    Rectangle()
                        .fill(Color(white: 0.15))
                        .overlay {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                }
            }
            #if os(tvOS)
            .frame(width: 80, height: 80)
            #else
            .frame(width: 60, height: 60)
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title ?? "Unknown Album")
                    #if os(tvOS)
                    .font(.system(size: 22, weight: .medium))
                    #else
                    .font(.headline)
                    #endif
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let year = album.year {
                        Text(String(year))
                    }
                    if let trackCount = album.leafCount {
                        Text("\(trackCount) tracks")
                    }
                }
                #if os(tvOS)
                .font(.system(size: 18))
                #else
                .font(.caption)
                #endif
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        #if os(tvOS)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        #else
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        #endif
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        #if os(tvOS)
        .hoverEffect(.highlight)
        #endif
    }

    private var thumbURL: URL? {
        guard let thumb = album.thumb else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(authToken)")
    }
}


#Preview {
    let sampleMovie = PlexMetadata(
        ratingKey: "123",
        key: "/library/metadata/123",
        type: "movie",
        title: "Sample Movie",
        contentRating: "PG-13",
        summary: "This is a sample movie summary that describes the plot and gives viewers an idea of what to expect.",
        tagline: "An epic adventure awaits",
        year: 2024,
        duration: 7200000 // 2 hours
    )

    PlexDetailView(item: sampleMovie)
}
