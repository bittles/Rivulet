//
//  TrailerPlayerView.swift
//  Rivulet
//
//  Simple player for trailers and extras using MPV
//

import SwiftUI

struct TrailerPlayerView: View {
    let trailer: PlexExtra
    let serverURL: String
    let authToken: String

    @Environment(\.dismiss) private var dismiss
    @State private var playerController: MPVMetalViewController?
    @State private var streamURL: URL?
    @State private var isLoading = true
    @State private var showControls = false
    @State private var controlsTimer: Timer?
    @State private var isPaused = false

    private let networkManager = PlexNetworkManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = streamURL {
                MPVPlayerView(
                    url: url,
                    headers: ["X-Plex-Token": authToken],
                    startTime: nil,
                    delegate: nil,
                    playerController: $playerController
                )
                .ignoresSafeArea()
            }

            // Loading overlay
            if isLoading {
                ProgressView("Loading trailer...")
                    .tint(.white)
            }

            // Simple controls overlay
            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showControls)
        .focusable()
        .onTapGesture {
            showControlsTemporarily()
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            playerController?.togglePause()
            isPaused.toggle()
        }
        .onExitCommand {
            dismiss()
        }
        .onMoveCommand { _ in
            showControlsTemporarily()
        }
        #endif
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            controlsTimer?.invalidate()
            playerController?.stop()
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            // Top bar with title
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trailer.title ?? "Trailer")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    if let type = trailer.extraType {
                        Text(extraTypeName(type))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 60)
            .padding(.top, 50)

            Spacer()

            // Bottom playback controls
            HStack(spacing: 40) {
                Button {
                    playerController?.seekRelative(by: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    playerController?.togglePause()
                    isPaused.toggle()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    playerController?.seekRelative(by: 10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 80)
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Setup

    private func setupPlayer() {
        // Debug: log trailer info
        print("🎬 [Trailer] Title: \(trailer.title ?? "unknown")")
        print("🎬 [Trailer] Key: \(trailer.key ?? "nil")")
        print("🎬 [Trailer] RatingKey: \(trailer.ratingKey ?? "nil")")

        guard let ratingKey = trailer.ratingKey else {
            print("🎬 [Trailer] No ratingKey available")
            return
        }

        // Fetch trailer metadata to get the actual media part key
        Task {
            await fetchAndPlayTrailer(ratingKey: ratingKey)
        }
    }

    private func fetchAndPlayTrailer(ratingKey: String) async {
        print("🎬 [Trailer] Fetching metadata for ratingKey: \(ratingKey)")

        // Fetch the trailer's full metadata to get the media part key
        guard let url = URL(string: "\(serverURL)/library/metadata/\(ratingKey)?X-Plex-Token=\(authToken)") else {
            print("🎬 [Trailer] Failed to build metadata URL")
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)

            // Parse the response to get the part key
            let decoder = JSONDecoder()
            let response = try decoder.decode(PlexMediaContainerWrapper.self, from: data)

            guard let metadata = response.MediaContainer.Metadata?.first,
                  let media = metadata.Media?.first,
                  let part = media.Part?.first else {
                print("🎬 [Trailer] No media part found in metadata")
                // Fall back to direct stream
                await fallbackToDirectStream(ratingKey: ratingKey)
                return
            }

            let partKey = part.key
            print("🎬 [Trailer] Found part key: \(partKey)")

            // Build direct play URL with the part key
            guard let streamUrl = networkManager.buildStreamURL(
                serverURL: serverURL,
                authToken: authToken,
                ratingKey: ratingKey,
                partKey: partKey,
                strategy: .directPlay
            ) else {
                print("🎬 [Trailer] Failed to build stream URL, trying direct stream")
                await fallbackToDirectStream(ratingKey: ratingKey)
                return
            }

            print("🎬 [Trailer] Playing: \(streamUrl)")
            await MainActor.run {
                self.streamURL = streamUrl
                self.isLoading = false
            }
        } catch {
            print("🎬 [Trailer] Error fetching metadata: \(error)")
            await fallbackToDirectStream(ratingKey: ratingKey)
        }
    }

    private func fallbackToDirectStream(ratingKey: String) async {
        print("🎬 [Trailer] Falling back to direct stream")
        guard let url = networkManager.buildStreamURL(
            serverURL: serverURL,
            authToken: authToken,
            ratingKey: ratingKey,
            strategy: .directStream
        ) else {
            print("🎬 [Trailer] Direct stream also failed")
            return
        }

        await MainActor.run {
            self.streamURL = url
            self.isLoading = false
        }
    }

    private func showControlsTemporarily() {
        controlsTimer?.invalidate()
        showControls = true

        controlsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            showControls = false
        }
    }

    private func extraTypeName(_ type: Int) -> String {
        switch type {
        case 1: return "Trailer"
        case 2: return "Deleted Scene"
        case 3: return "Featurette"
        case 4: return "Behind the Scenes"
        case 5: return "Interview"
        case 6: return "Scene"
        case 7: return "Short"
        default: return "Extra"
        }
    }
}
