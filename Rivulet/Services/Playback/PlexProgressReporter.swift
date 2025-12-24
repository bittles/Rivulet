//
//  PlexProgressReporter.swift
//  Rivulet
//
//  Reports playback progress to Plex server for timeline tracking
//

import Foundation

/// Reports playback progress and watch status to Plex server
actor PlexProgressReporter {
    static let shared = PlexProgressReporter()

    private let networkManager = PlexNetworkManager.shared
    private var lastReportedTimes: [String: TimeInterval] = [:]

    private init() {}

    // MARK: - Progress Reporting

    /// Reports current playback position to Plex
    /// - Parameters:
    ///   - ratingKey: The Plex rating key for the media item
    ///   - time: Current playback time in seconds
    ///   - duration: Total duration in seconds
    ///   - state: Playback state ("playing", "paused", "stopped")
    func reportProgress(
        ratingKey: String,
        time: TimeInterval,
        duration: TimeInterval,
        state: String
    ) async {
        guard !ratingKey.isEmpty else { return }

        // Throttle reports - only report if time changed significantly
        if let lastTime = lastReportedTimes[ratingKey], abs(time - lastTime) < 5 {
            return
        }
        lastReportedTimes[ratingKey] = time

        guard let server = await getServer() else { return }

        let timeMs = Int(time * 1000)
        let durationMs = Int(duration * 1000)

        // Build timeline URL
        var components = URLComponents(string: "\(server.address)/:/timeline")
        components?.queryItems = [
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "key", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "time", value: String(timeMs)),
            URLQueryItem(name: "duration", value: String(durationMs)),
            URLQueryItem(name: "X-Plex-Token", value: server.token),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexAPI.clientIdentifier),
            URLQueryItem(name: "X-Plex-Platform", value: PlexAPI.platform),
            URLQueryItem(name: "X-Plex-Device", value: PlexAPI.deviceName),
            URLQueryItem(name: "X-Plex-Product", value: PlexAPI.productName)
        ]

        guard let url = components?.url else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(server.token, forHTTPHeaderField: "X-Plex-Token")

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("PlexProgressReporter: Timeline report failed with status \(httpResponse.statusCode)")
            }
        } catch {
            print("PlexProgressReporter: Failed to report progress: \(error)")
        }
    }

    /// Marks an item as fully watched (scrobble)
    /// - Parameter ratingKey: The Plex rating key for the media item
    func markAsWatched(ratingKey: String) async {
        guard !ratingKey.isEmpty else { return }
        guard let server = await getServer() else { return }

        let urlString = "\(server.address)/:/scrobble?identifier=com.plexapp.plugins.library&key=\(ratingKey)&X-Plex-Token=\(server.token)"

        guard let url = URL(string: urlString) else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("PlexProgressReporter: Marked \(ratingKey) as watched")
                } else {
                    print("PlexProgressReporter: Scrobble failed with status \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("PlexProgressReporter: Failed to mark as watched: \(error)")
        }
    }

    /// Marks an item as unwatched
    /// - Parameter ratingKey: The Plex rating key for the media item
    func markAsUnwatched(ratingKey: String) async {
        guard !ratingKey.isEmpty else { return }
        guard let server = await getServer() else { return }

        let urlString = "\(server.address)/:/unscrobble?identifier=com.plexapp.plugins.library&key=\(ratingKey)&X-Plex-Token=\(server.token)"

        guard let url = URL(string: urlString) else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (_, _) = try await URLSession.shared.data(for: request)
            print("PlexProgressReporter: Marked \(ratingKey) as unwatched")
        } catch {
            print("PlexProgressReporter: Failed to mark as unwatched: \(error)")
        }
    }

    // MARK: - Helpers

    private func getServer() async -> (address: String, token: String)? {
        await MainActor.run {
            let authManager = PlexAuthManager.shared
            guard let address = authManager.selectedServerURL,
                  let token = authManager.authToken else {
                return nil
            }
            return (address, token)
        }
    }
}
