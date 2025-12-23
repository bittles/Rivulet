//
//  TrailerPlayerView.swift
//  Rivulet
//
//  Simple player for trailers and extras
//

import SwiftUI
import AVKit

struct TrailerPlayerView: View {
    let trailer: PlexExtra
    let serverURL: String
    let authToken: String

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    private let networkManager = PlexNetworkManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView("Loading trailer...")
                    .tint(.white)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func setupPlayer() {
        guard let ratingKey = trailer.ratingKey else {
            print("No trailer ratingKey available")
            return
        }

        // Build a proper streaming URL using the transcode endpoint
        // Trailers are usually small files that can direct stream
        guard let url = networkManager.buildStreamURL(
            serverURL: serverURL,
            authToken: authToken,
            ratingKey: ratingKey,
            strategy: .hlsTranscode  // Use HLS for trailers for compatibility
        ) else {
            print("Failed to build trailer stream URL")
            return
        }

        print("Playing trailer: \(url)")
        let avPlayer = AVPlayer(url: url)
        self.player = avPlayer
        avPlayer.play()
    }
}
