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

    private let networkManager = PlexNetworkManager.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero Section with backdrop
                heroSection

                // Content Section
                VStack(alignment: .leading, spacing: 32) {
                    // Title and metadata
                    headerSection

                    // Action buttons
                    actionButtons

                    // Summary
                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }

                    // TV Show specific: Seasons and Episodes
                    if item.type == "show" {
                        seasonSection
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 32)
                .padding(.bottom, 80)
            }
        }
        .ignoresSafeArea(edges: .top)
        .task {
            if item.type == "show" {
                await loadSeasons()
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            // Play the selected episode if available, otherwise play the main item (movie)
            if let episode = selectedEpisode {
                VideoPlayerView(item: episode)
            } else {
                VideoPlayerView(item: item)
            }
        }
        .onChange(of: showPlayer) { _, isShowing in
            // Clear selected episode when player closes
            if !isShowing {
                selectedEpisode = nil
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Background art
            AsyncImage(url: artURL) { phase in
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
                @unknown default:
                    Color.black
                }
            }
            .frame(height: 600)
            .clipped()
            .overlay {
                // Gradient overlay for text readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            // Poster overlay
            HStack(alignment: .bottom, spacing: 32) {
                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay { ProgressView() }
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay {
                                Image(systemName: item.type == "movie" ? "film" : "tv")
                                    .font(.largeTitle)
                            }
                    @unknown default:
                        Color.gray
                    }
                }
                .frame(width: 200, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 10)

                Spacer()
            }
            .padding(.horizontal, 48)
            .padding(.bottom, -50) // Overlap into content area
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Spacer for poster overlap
            Spacer()
                .frame(height: 60)

            Text(item.title ?? "Unknown Title")
                .font(.largeTitle)
                .fontWeight(.bold)

            HStack(spacing: 16) {
                if let year = item.year {
                    Text(String(year))
                }

                if let contentRating = item.contentRating {
                    Text(contentRating)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary, lineWidth: 1)
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
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let tagline = item.tagline {
                Text(tagline)
                    .font(.headline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 20) {
            // Play button
            Button {
                showPlayer = true
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text(item.isInProgress ? "Resume" : "Play")
                }
                .font(.headline)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)

            // If in progress, show progress info
            if let progress = item.viewOffsetFormatted, item.isInProgress {
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
                }
            }
        }
    }

    // MARK: - Data Loading

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

    // MARK: - URL Helpers

    private var artURL: URL? {
        guard let art = item.bestArt,
              let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else { return nil }
        return URL(string: "\(serverURL)\(art)?X-Plex-Token=\(token)")
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
                AsyncImage(url: thumbURL) { phase in
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
                    @unknown default:
                        Color.gray
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
