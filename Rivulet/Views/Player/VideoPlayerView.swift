//
//  VideoPlayerView.swift
//  Rivulet
//
//  Full-screen video player using AVPlayerViewController
//

import SwiftUI
import AVKit
import Combine

struct VideoPlayerView: View {
    let item: PlexMetadata
    var startOffset: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = PlexAuthManager.shared
    @StateObject private var playbackManager = PlaybackManager.shared

    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if isLoading {
                loadingView
            } else if hasError {
                errorView
            } else if let player = playbackManager.player {
                VideoPlayerRepresentable(player: player)
                    .ignoresSafeArea()
            }
        }
        .task {
            await startPlayback()
        }
        .onDisappear {
            playbackManager.stop()
        }
        .onReceive(playbackManager.$error) { error in
            if let error = error {
                hasError = true
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2)

            Text("Loading...")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(item.title ?? "")
                .font(.headline)
        }
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)

            Text("Playback Error")
                .font(.title)

            Text(errorMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.top, 20)
        }
    }

    // MARK: - Playback

    private func startPlayback() async {
        guard let serverURL = authManager.selectedServerURL,
              let token = authManager.authToken else {
            hasError = true
            errorMessage = "Not authenticated"
            isLoading = false
            return
        }

        await playbackManager.play(
            item: item,
            serverURL: serverURL,
            authToken: token,
            startOffset: startOffset
        )

        isLoading = false
    }
}

// MARK: - AVPlayerViewController Wrapper

#if os(tvOS)
struct VideoPlayerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
#else
// macOS/iOS preview support
struct VideoPlayerRepresentable: View {
    let player: AVPlayer

    var body: some View {
        VideoPlayer(player: player)
    }
}
#endif

// MARK: - Episode Player Wrapper

/// Convenience view for playing episodes with show context
struct EpisodePlayerView: View {
    let episode: PlexMetadata
    let showTitle: String?

    var body: some View {
        VideoPlayerView(item: episode)
    }
}

#Preview {
    let sampleMovie = PlexMetadata(
        ratingKey: "123",
        key: "/library/metadata/123",
        type: "movie",
        title: "Sample Movie",
        year: 2024,
        duration: 7200000
    )

    VideoPlayerView(item: sampleMovie)
}
