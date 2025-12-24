//
//  PlexNetworkManager.swift
//  Rivulet
//
//  Adapted from plex_watchOS NetworkManager.swift
//  Original created by Bain Gurley on 4/19/24.
//
//  This manager handles all Plex API communication with:
//  - SSL/TLS handling for self-signed certificates
//  - Priority queue system for network requests
//  - Server discovery and authentication
//  - Library browsing and content fetching
//

import Foundation

// MARK: - Network Priority

enum NetworkPriority {
    case high      // Current playback / critical operations
    case medium    // GUI-affecting API calls
    case low       // Prefetching / background operations
}

// MARK: - Plex Network Manager

@MainActor
class PlexNetworkManager: NSObject {
    static let shared = PlexNetworkManager()

    // Default timeout for requests
    private let defaultTimeout: TimeInterval = 30.0

    // URL session with custom delegate for self-signed certs
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = defaultTimeout
        configuration.timeoutIntervalForResource = defaultTimeout * 2
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    // MARK: - Core Request Methods

    /// Execute a request and return decoded data
    func request<T: Decodable>(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = defaultTimeout

        // Default headers
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        // Add custom headers
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        print("🌐 PlexNetwork: \(method) \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("🌐 PlexNetwork: ❌ Invalid response type")
            throw PlexAPIError.invalidResponse
        }

        print("🌐 PlexNetwork: Response \(httpResponse.statusCode) (\(data.count) bytes)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("🌐 PlexNetwork: ❌ HTTP Error \(httpResponse.statusCode)")
            if let responseStr = String(data: data, encoding: .utf8) {
                print("🌐 PlexNetwork: Response body: \(responseStr.prefix(500))")
            }
            throw PlexAPIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        // Debug: print first part of response
        if let responseStr = String(data: data, encoding: .utf8) {
            print("🌐 PlexNetwork: Response preview: \(responseStr.prefix(300))...")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("🌐 PlexNetwork: ❌ Decode error: \(error)")
            if let responseStr = String(data: data, encoding: .utf8) {
                print("🌐 PlexNetwork: Full response: \(responseStr)")
            }
            throw error
        }
    }

    /// Execute a request and return raw data
    func requestData(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = defaultTimeout

        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PlexAPIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        return data
    }

    // MARK: - Authentication

    /// Request a PIN code for authentication
    func requestPin() async throws -> (pinCode: String, pinId: Int) {
        let url = URL(string: "https://plex.tv/api/v2/pins")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue(PlexAPI.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(PlexAPI.productName, forHTTPHeaderField: "X-Plex-Product")
        request.addValue(PlexAPI.platform, forHTTPHeaderField: "X-Plex-Platform")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            throw PlexAPIError.authenticationFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pinId = json["id"] as? Int,
              let pinCode = json["code"] as? String else {
            throw PlexAPIError.parsingError
        }

        return (pinCode, pinId)
    }

    /// Check if PIN has been authenticated
    func checkPinAuthentication(pinId: Int) async throws -> String? {
        let url = URL(string: "https://plex.tv/api/v2/pins/\(pinId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue(PlexAPI.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.invalidResponse
        }

        if httpResponse.statusCode == 400 {
            throw PlexAPIError.authenticationFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlexAPIError.parsingError
        }

        // authToken will be nil if not yet authenticated
        return json["authToken"] as? String
    }

    // MARK: - Server Discovery

    /// Get list of available Plex servers for the authenticated user
    func getServers(authToken: String) async throws -> [PlexDevice] {
        let url = URL(string: "\(PlexAPI.baseUrl)/api/v2/resources")!

        let devices: [PlexDevice] = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        // Filter to only Plex Media Servers
        return devices.filter { $0.provides == "server" }
    }

    // MARK: - Library Browsing

    /// Get all library sections (Movies, TV Shows, etc.)
    func getLibraries(serverURL: String, authToken: String) async throws -> [PlexLibrary] {
        guard let url = URL(string: "\(serverURL)/library/sections") else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexLibraryContainer = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Directory ?? []
    }

    /// Get all items in a library section
    func getLibraryItems(
        serverURL: String,
        authToken: String,
        sectionId: String,
        start: Int = 0,
        size: Int = 100
    ) async throws -> [PlexMetadata] {
        guard var components = URLComponents(string: "\(serverURL)/library/sections/\(sectionId)/all") else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(start)"),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(size)")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Metadata ?? []
    }

    /// Get library items with total count for pagination
    /// - Returns: Tuple of (items, totalSize) where totalSize indicates total items in the library
    func getLibraryItemsWithTotal(
        serverURL: String,
        authToken: String,
        sectionId: String,
        start: Int = 0,
        size: Int = 100
    ) async throws -> (items: [PlexMetadata], totalSize: Int?) {
        guard var components = URLComponents(string: "\(serverURL)/library/sections/\(sectionId)/all") else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(start)"),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(size)")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        let items = container.MediaContainer.Metadata ?? []
        let totalSize = container.MediaContainer.totalSize

        return (items, totalSize)
    }

    /// Get item metadata by rating key
    func getMetadata(
        serverURL: String,
        authToken: String,
        ratingKey: String
    ) async throws -> PlexMetadata {
        guard let url = URL(string: "\(serverURL)/library/metadata/\(ratingKey)") else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        guard let item = container.MediaContainer.Metadata?.first else {
            throw PlexAPIError.notFound
        }

        return item
    }

    /// Get full metadata including cast, crew, and extras
    func getFullMetadata(
        serverURL: String,
        authToken: String,
        ratingKey: String
    ) async throws -> PlexMetadata {
        guard var components = URLComponents(string: "\(serverURL)/library/metadata/\(ratingKey)") else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "includeExtras", value: "1"),
            URLQueryItem(name: "includeOnDeck", value: "1"),
            URLQueryItem(name: "includeChapters", value: "1"),
            URLQueryItem(name: "includeRelated", value: "0"),
            URLQueryItem(name: "includeMarkers", value: "1")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        guard let item = container.MediaContainer.Metadata?.first else {
            throw PlexAPIError.notFound
        }

        return item
    }

    /// Get related items (similar content)
    func getRelatedItems(
        serverURL: String,
        authToken: String,
        ratingKey: String,
        limit: Int = 12
    ) async throws -> [PlexMetadata] {
        guard var components = URLComponents(string: "\(serverURL)/library/metadata/\(ratingKey)/related") else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "count", value: "\(limit)")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Metadata ?? []
    }

    /// Get extras (trailers, behind the scenes, etc.)
    func getExtras(
        serverURL: String,
        authToken: String,
        ratingKey: String
    ) async throws -> [PlexExtra] {
        guard let url = URL(string: "\(serverURL)/library/metadata/\(ratingKey)/extras") else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexExtrasContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Metadata ?? []
    }

    /// Get children of an item (seasons for shows, episodes for seasons)
    func getChildren(
        serverURL: String,
        authToken: String,
        ratingKey: String
    ) async throws -> [PlexMetadata] {
        guard let url = URL(string: "\(serverURL)/library/metadata/\(ratingKey)/children") else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Metadata ?? []
    }

    // MARK: - Continue Watching / On Deck

    /// Get "On Deck" items (continue watching)
    func getOnDeck(serverURL: String, authToken: String) async throws -> [PlexMetadata] {
        guard let url = URL(string: "\(serverURL)/library/onDeck") else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Metadata ?? []
    }

    /// Get recently added items
    func getRecentlyAdded(
        serverURL: String,
        authToken: String,
        sectionId: String? = nil,
        limit: Int = 20
    ) async throws -> [PlexMetadata] {
        var urlString = "\(serverURL)/library/recentlyAdded"
        if let section = sectionId {
            urlString = "\(serverURL)/library/sections/\(section)/recentlyAdded"
        }

        guard var components = URLComponents(string: urlString) else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Metadata ?? []
    }

    // MARK: - Hubs (Home Screen Sections)

    /// Get home screen hubs (global recommendations)
    /// - Parameter count: Number of items per hub (default 24, Plex defaults to ~6)
    func getHubs(serverURL: String, authToken: String, count: Int = 24) async throws -> [PlexHub] {
        guard var components = URLComponents(string: "\(serverURL)/hubs") else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "count", value: "\(count)")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Hub ?? []
    }

    /// Get library-specific hubs (recommendations for a specific library section)
    /// Returns Continue Watching, Recently Added, Recently Released, etc. for that library
    /// - Parameter count: Number of items per hub (default 24, Plex defaults to ~6)
    func getLibraryHubs(serverURL: String, authToken: String, sectionId: String, count: Int = 24) async throws -> [PlexHub] {
        guard var components = URLComponents(string: "\(serverURL)/hubs/sections/\(sectionId)") else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "count", value: "\(count)")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Hub ?? []
    }

    /// Get more items from a hub using its key (for pagination/infinite scroll)
    /// - Parameters:
    ///   - hubKey: The hub's key path (e.g., "/hubs/sections/1/continueWatching")
    ///   - start: Starting index for pagination
    ///   - count: Number of items to fetch
    /// - Returns: Tuple of (items, totalSize) where totalSize indicates if more items exist
    func getHubItems(
        serverURL: String,
        authToken: String,
        hubKey: String,
        start: Int = 0,
        count: Int = 24
    ) async throws -> (items: [PlexMetadata], totalSize: Int?) {
        // The hubKey might be a full path like "/hubs/sections/1/continueWatching"
        // or just the section like "hub.movies.recentlyadded"
        let fullPath: String
        if hubKey.hasPrefix("/") {
            fullPath = "\(serverURL)\(hubKey)"
        } else {
            fullPath = "\(serverURL)/\(hubKey)"
        }

        guard var components = URLComponents(string: fullPath) else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(start)"),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(count)")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        let items = container.MediaContainer.Metadata ?? []
        let totalSize = container.MediaContainer.size

        return (items, totalSize)
    }

    // MARK: - Progress Reporting

    /// Report playback progress to Plex
    func reportProgress(
        serverURL: String,
        authToken: String,
        ratingKey: String,
        timeMs: Int,
        state: String = "playing",
        duration: Int? = nil
    ) async throws {
        guard var components = URLComponents(string: "\(serverURL)/:/timeline") else {
            throw PlexAPIError.invalidURL
        }

        var queryItems = [
            URLQueryItem(name: "key", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "time", value: "\(timeMs)"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library")
        ]

        if let dur = duration {
            queryItems.append(URLQueryItem(name: "duration", value: "\(dur)"))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        for (key, value) in plexHeaders(authToken: authToken) {
            request.addValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlexAPIError.invalidResponse
        }
    }

    /// Mark item as watched
    func markWatched(
        serverURL: String,
        authToken: String,
        ratingKey: String
    ) async throws {
        guard var components = URLComponents(string: "\(serverURL)/:/scrobble") else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        print("🎬 Marking as watched: \(ratingKey) - URL: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        for (key, value) in plexHeaders(authToken: authToken) {
            request.addValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let httpResponse = response as? HTTPURLResponse {
                throw PlexAPIError.httpError(statusCode: httpResponse.statusCode, data: nil)
            }
            throw PlexAPIError.invalidResponse
        }

        print("🎬 Successfully marked as watched: \(ratingKey)")
    }

    /// Mark item as unwatched
    func markUnwatched(
        serverURL: String,
        authToken: String,
        ratingKey: String
    ) async throws {
        guard var components = URLComponents(string: "\(serverURL)/:/unscrobble") else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        print("🎬 Marking as unwatched: \(ratingKey) - URL: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        for (key, value) in plexHeaders(authToken: authToken) {
            request.addValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let httpResponse = response as? HTTPURLResponse {
                throw PlexAPIError.httpError(statusCode: httpResponse.statusCode, data: nil)
            }
            throw PlexAPIError.invalidResponse
        }

        print("🎬 Successfully marked as unwatched: \(ratingKey)")
    }

    /// Refresh metadata for an item (re-fetch from metadata agents)
    func refreshMetadata(
        serverURL: String,
        authToken: String,
        ratingKey: String
    ) async throws {
        guard let url = URL(string: "\(serverURL)/library/metadata/\(ratingKey)/refresh") else {
            throw PlexAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"

        for (key, value) in plexHeaders(authToken: authToken) {
            request.addValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlexAPIError.invalidResponse
        }
    }

    /// Remove item from continue watching by marking as unwatched
    func removeFromContinueWatching(
        serverURL: String,
        authToken: String,
        ratingKey: String
    ) async throws {
        // Mark as unwatched clears all progress and removes from "Continue Watching"
        print("🎬 Removing from Continue Watching: \(ratingKey)")
        try await markUnwatched(
            serverURL: serverURL,
            authToken: authToken,
            ratingKey: ratingKey
        )
        print("🎬 Successfully removed from Continue Watching: \(ratingKey)")
    }

    // MARK: - Streaming URLs
    
    /// Playback strategy - ordered by preference
    enum PlaybackStrategy: String, CaseIterable {
        case directPlay = "Direct Play"          // Play file directly, no processing
        case directStream = "Direct Stream"      // Remux container only, no transcoding
        case hlsTranscode = "HLS Transcode"      // Full transcode to HLS
        
        var next: PlaybackStrategy? {
            switch self {
            case .directPlay: return .directStream
            case .directStream: return .hlsTranscode
            case .hlsTranscode: return nil
            }
        }
    }

    /// Build streaming URL for the given strategy
    /// - Parameter container: The file container format (mp4, mkv, etc.) to determine direct play eligibility
    func buildStreamURL(
        serverURL: String,
        authToken: String,
        ratingKey: String,
        partKey: String? = nil,
        container: String? = nil,
        strategy: PlaybackStrategy = .directPlay,
        offsetMs: Int = 0
    ) -> URL? {
        switch strategy {
        case .directPlay:
            // Apple TV can only direct play MP4/MOV/M4V containers
            // MKV, AVI, etc. require remuxing even if codecs are compatible
            let directPlayableContainers = ["mp4", "m4v", "mov"]
            let containerLower = container?.lowercased() ?? ""
            
            if !directPlayableContainers.contains(containerLower) && !containerLower.isEmpty {
                print("📦 Container '\(containerLower)' not direct-playable, skipping Direct Play")
                return nil  // Signal to try next strategy
            }
            return buildDirectPlayURL(serverURL: serverURL, authToken: authToken, partKey: partKey, ratingKey: ratingKey)
        case .directStream:
            return buildDirectStreamURL(serverURL: serverURL, authToken: authToken, ratingKey: ratingKey, offsetMs: offsetMs)
        case .hlsTranscode:
            return buildHLSTranscodeURL(serverURL: serverURL, authToken: authToken, ratingKey: ratingKey, offsetMs: offsetMs)
        }
    }
    
    /// Direct play - stream the file as-is (most efficient)
    /// Apple TV supports: H.264, HEVC (4K), AAC, AC3, E-AC3, and most common containers
    private func buildDirectPlayURL(
        serverURL: String,
        authToken: String,
        partKey: String?,
        ratingKey: String
    ) -> URL? {
        // Use the part key if available, otherwise construct from rating key
        let path = partKey ?? "/library/parts/\(ratingKey)/file"

        guard var components = URLComponents(string: "\(serverURL)\(path)") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: authToken),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexAPI.clientIdentifier),
            URLQueryItem(name: "X-Plex-Platform", value: PlexAPI.platform),
            URLQueryItem(name: "X-Plex-Device", value: PlexAPI.deviceName)
        ]

        return components.url
    }

    /// VLC Direct Play - streams the raw file without any transcoding
    /// VLCKit can play virtually any format: MKV, HEVC, H264, DTS, TrueHD, ASS/SSA subs, etc.
    /// This is the most efficient option and preserves all original quality/tracks
    func buildVLCDirectPlayURL(
        serverURL: String,
        authToken: String,
        partKey: String
    ) -> URL? {
        guard var components = URLComponents(string: "\(serverURL)\(partKey)") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: authToken),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexAPI.clientIdentifier),
            URLQueryItem(name: "X-Plex-Platform", value: PlexAPI.platform),
            URLQueryItem(name: "X-Plex-Device", value: PlexAPI.deviceName),
            URLQueryItem(name: "X-Plex-Product", value: PlexAPI.productName)
        ]

        if let url = components.url {
            print("🎬 VLC Direct Play URL: \(url.absoluteString)")
        }

        return components.url
    }
    
    /// Direct stream - remux container only, copy video stream
    /// Only transcodes audio if incompatible (like DTS → AAC)
    /// Video is passed through unchanged (no re-encoding)
    func buildDirectStreamURL(
        serverURL: String,
        authToken: String,
        ratingKey: String,
        offsetMs: Int = 0
    ) -> URL? {
        guard var components = URLComponents(string: "\(serverURL)/video/:/transcode/universal/start.m3u8") else {
            return nil
        }

        let sessionId = UUID().uuidString

        // Client profile tells Plex exactly what codecs Apple TV can handle natively
        // This is CRITICAL for direct stream - without it, Plex will transcode everything
        // Apple TV 4K supports: H.264, HEVC (including Main 10 for HDR), AAC, AC3, E-AC3
        // Prefer HLS fMP4 for HEVC direct stream (remux) instead of MPEG-TS.
        let clientProfile = [
            // Direct stream profiles - what we can play without any transcoding
            "add-direct-stream-profile(type=videoProfile&videoCodec=h264&container=mp4)",
            "add-direct-stream-profile(type=videoProfile&videoCodec=h264&container=mpegts)",
            "add-direct-stream-profile(type=videoProfile&videoCodec=hevc&container=mp4)",
            "add-direct-stream-profile(type=musicProfile&audioCodec=aac&container=mp4)",
            "add-direct-stream-profile(type=musicProfile&audioCodec=ac3&container=mp4)",
            "add-direct-stream-profile(type=musicProfile&audioCodec=eac3&container=mp4)",
            "add-direct-stream-profile(type=musicProfile&audioCodec=aac&container=mpegts)",
            "add-direct-stream-profile(type=musicProfile&audioCodec=ac3&container=mpegts)",
            "add-direct-stream-profile(type=musicProfile&audioCodec=eac3&container=mpegts)",
            // Transcode target - if we MUST transcode, use these settings
            "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mp4&videoCodec=h264&audioCodec=aac,ac3,eac3)",
            "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mp4&videoCodec=hevc&audioCodec=aac,ac3,eac3)",
            "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mpegts&videoCodec=h264&audioCodec=aac,ac3,eac3)",
        ].joined(separator: "+")

        components.queryItems = [
            // Authentication
            URLQueryItem(name: "X-Plex-Token", value: authToken),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexAPI.clientIdentifier),
            URLQueryItem(name: "X-Plex-Platform", value: PlexAPI.platform),
            URLQueryItem(name: "X-Plex-Device", value: PlexAPI.deviceName),
            URLQueryItem(name: "X-Plex-Product", value: PlexAPI.productName),

            // CRITICAL: Client profile tells Plex what we support for direct streaming
            URLQueryItem(name: "X-Plex-Client-Profile-Extra", value: clientProfile),

            // Media reference
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "offset", value: "\(offsetMs / 1000)"),

            // CRITICAL: Direct stream settings for video passthrough
            // directPlay=0: Don't try to play file directly (container not supported)
            // directStream=1: Copy video stream (no re-encoding!)
            // directStreamAudio=1: Copy audio stream too (AAC/AC3/EAC3 supported)
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "container", value: "mp4"),
            URLQueryItem(name: "segmentFormat", value: "mp4"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "directStreamAudio", value: "1"),
            URLQueryItem(name: "fastSeek", value: "1"),

            // Video settings - tell Plex these are acceptable for output
            // Must match client profile for direct stream to work
            URLQueryItem(name: "videoCodec", value: "h264,hevc"),
            URLQueryItem(name: "videoQuality", value: "100"),
            URLQueryItem(name: "videoResolution", value: "4096x2160"),
            URLQueryItem(name: "maxVideoBitrate", value: "200000"),

            // Audio - these codecs can be direct streamed
            URLQueryItem(name: "audioCodec", value: "aac,ac3,eac3"),
            URLQueryItem(name: "audioBitrate", value: "640"),
            URLQueryItem(name: "audioChannels", value: "8"),

            // Subtitles
            URLQueryItem(name: "subtitles", value: "auto"),
            URLQueryItem(name: "subtitleSize", value: "100"),

            // Context - streaming on local network
            URLQueryItem(name: "context", value: "streaming"),
            URLQueryItem(name: "location", value: "lan"),

            // Session
            URLQueryItem(name: "session", value: sessionId),

            // Prevent auto quality reduction
            URLQueryItem(name: "autoAdjustQuality", value: "0"),
            URLQueryItem(name: "hasMDE", value: "1")
        ]

        if let url = components.url {
            print("🎬 Direct Stream URL generated:")
            print("   Client Profile: \(clientProfile)")
            print("   Full URL: \(url.absoluteString.prefix(500))...")
        }

        return components.url
    }

    /// HLS transcode - full transcode to H.264/AAC HLS stream
    /// Use as fallback when direct play/stream fails
    func buildHLSTranscodeURL(
        serverURL: String,
        authToken: String,
        ratingKey: String,
        offsetMs: Int = 0
    ) -> URL? {
        guard var components = URLComponents(string: "\(serverURL)/video/:/transcode/universal/start.m3u8") else {
            return nil
        }

        let sessionId = UUID().uuidString

        components.queryItems = [
            // Authentication
            URLQueryItem(name: "X-Plex-Token", value: authToken),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexAPI.clientIdentifier),
            URLQueryItem(name: "X-Plex-Platform", value: PlexAPI.platform),
            URLQueryItem(name: "X-Plex-Device", value: PlexAPI.deviceName),
            URLQueryItem(name: "X-Plex-Product", value: PlexAPI.productName),

            // Media reference
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "offset", value: "\(offsetMs / 1000)"),

            // Force transcode to H264/AAC for maximum compatibility
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "0"),
            URLQueryItem(name: "directStreamAudio", value: "0"),

            // Video settings - H264 high profile
            URLQueryItem(name: "videoCodec", value: "h264"),
            URLQueryItem(name: "videoResolution", value: "1920x1080"),
            URLQueryItem(name: "maxVideoBitrate", value: "20000"),
            URLQueryItem(name: "videoQuality", value: "100"),
            URLQueryItem(name: "h264Level", value: "42"),
            URLQueryItem(name: "h264Profile", value: "high"),

            // Audio settings - AAC 5.1
            URLQueryItem(name: "audioCodec", value: "aac"),
            URLQueryItem(name: "audioBitrate", value: "384"),
            URLQueryItem(name: "audioChannels", value: "6"),
            URLQueryItem(name: "audioBoost", value: "100"),

            // Disable subtitles to simplify transcode
            URLQueryItem(name: "subtitles", value: "none"),
            URLQueryItem(name: "subtitleSize", value: "100"),
            URLQueryItem(name: "addDebugOverlay", value: "0"),

            // Context
            URLQueryItem(name: "context", value: "streaming"),
            URLQueryItem(name: "location", value: "lan"),

            // Session
            URLQueryItem(name: "session", value: sessionId),
            
            // Additional params for stability
            URLQueryItem(name: "autoAdjustQuality", value: "0"),
            URLQueryItem(name: "hasMDE", value: "1")
        ]

        return components.url
    }
    
    /// Get decision info from Plex about what playback method to use
    func getPlaybackDecision(
        serverURL: String,
        authToken: String,
        ratingKey: String
    ) async throws -> PlaybackDecision {
        guard var components = URLComponents(string: "\(serverURL)/video/:/transcode/universal/decision") else {
            throw PlexAPIError.invalidURL
        }
        
        components.queryItems = [
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "directPlay", value: "1"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "directStreamAudio", value: "1"),
            URLQueryItem(name: "videoCodec", value: "h264,hevc"),
            URLQueryItem(name: "audioCodec", value: "aac,ac3,eac3"),
            URLQueryItem(name: "X-Plex-Token", value: authToken),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexAPI.clientIdentifier),
            URLQueryItem(name: "X-Plex-Platform", value: PlexAPI.platform),
            URLQueryItem(name: "X-Plex-Device", value: PlexAPI.deviceName)
        ]
        
        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }
        
        let container: PlaybackDecisionContainer = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )
        
        return container.MediaContainer
    }

    /// Build thumbnail URL
    func buildThumbnailURL(
        serverURL: String,
        authToken: String,
        thumbPath: String,
        width: Int = 400,
        height: Int = 600
    ) -> URL? {
        guard var components = URLComponents(string: "\(serverURL)/photo/:/transcode") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "url", value: thumbPath),
            URLQueryItem(name: "width", value: "\(width)"),
            URLQueryItem(name: "height", value: "\(height)"),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "X-Plex-Token", value: authToken)
        ]

        return components.url
    }

    // MARK: - Search

    /// Search library
    func search(
        serverURL: String,
        authToken: String,
        query: String,
        sectionId: String? = nil,
        start: Int = 0,
        size: Int = 60
    ) async throws -> [PlexMetadata] {
        var urlString = "\(serverURL)/search"
        if let section = sectionId {
            urlString = "\(serverURL)/library/sections/\(section)/search"
        }

        guard var components = URLComponents(string: urlString) else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(start)"),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(size)")
        ]

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Metadata ?? []
    }

    // MARK: - Live TV

    /// Check if the Plex server supports Live TV
    func getLiveTVCapabilities(
        serverURL: String,
        authToken: String
    ) async throws -> PlexLiveTVCapabilities {
        // Check for DVR/tuner capability by requesting the livetv endpoint
        guard let url = URL(string: "\(serverURL)/livetv/dvrs") else {
            throw PlexAPIError.invalidURL
        }

        do {
            let container: PlexDVRContainer = try await request(
                url,
                headers: plexHeaders(authToken: authToken)
            )

            let hasDVRs = !(container.MediaContainer.Dvr?.isEmpty ?? true)
            return PlexLiveTVCapabilities(
                allowTuners: hasDVRs,
                liveTVEnabled: hasDVRs,
                hasDVR: hasDVRs
            )
        } catch {
            // If the endpoint fails, Live TV is not available
            return PlexLiveTVCapabilities()
        }
    }

    /// Get all Live TV channels
    func getLiveTVChannels(
        serverURL: String,
        authToken: String
    ) async throws -> [PlexLiveTVChannel] {
        guard let url = URL(string: "\(serverURL)/livetv/sessions") else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexLiveTVChannelContainer = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Metadata ?? []
    }

    /// Get Live TV guide (EPG) for specified channels and time range
    func getLiveTVGuide(
        serverURL: String,
        authToken: String,
        channelIds: [String]? = nil,
        startTime: Date,
        endTime: Date
    ) async throws -> [PlexLiveTVGuideChannel] {
        guard var components = URLComponents(string: "\(serverURL)/livetv/dvrs/1/channels") else {
            throw PlexAPIError.invalidURL
        }

        let startTimestamp = Int(startTime.timeIntervalSince1970)
        let endTimestamp = Int(endTime.timeIntervalSince1970)

        var queryItems = [
            URLQueryItem(name: "includeMeta", value: "1"),
            URLQueryItem(name: "beginsAt>", value: "\(startTimestamp)"),
            URLQueryItem(name: "endsAt<", value: "\(endTimestamp)")
        ]

        if let ids = channelIds, !ids.isEmpty {
            queryItems.append(URLQueryItem(name: "channelId", value: ids.joined(separator: ",")))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexLiveTVGuideContainer = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Metadata ?? []
    }

    /// Build Live TV stream URL for a channel
    func buildLiveTVStreamURL(
        serverURL: String,
        authToken: String,
        channelKey: String
    ) -> URL? {
        guard var components = URLComponents(string: "\(serverURL)\(channelKey)") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: authToken),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexAPI.clientIdentifier),
            URLQueryItem(name: "X-Plex-Platform", value: PlexAPI.platform),
            URLQueryItem(name: "X-Plex-Device", value: PlexAPI.deviceName),
            URLQueryItem(name: "X-Plex-Product", value: PlexAPI.productName)
        ]

        return components.url
    }

    // MARK: - Helper Methods

    private func plexHeaders(authToken: String) -> [String: String] {
        [
            "X-Plex-Token": authToken,
            "X-Plex-Client-Identifier": PlexAPI.clientIdentifier,
            "X-Plex-Product": PlexAPI.productName,
            "X-Plex-Platform": PlexAPI.platform,
            "X-Plex-Device": PlexAPI.deviceName
        ]
    }
}

// MARK: - URLSessionDelegate (SSL Certificate Handling)

extension PlexNetworkManager: URLSessionDelegate {
    /// Handle SSL certificate challenges for self-signed certificates
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        let port = challenge.protectionSpace.port

        // Trust self-signed certificates for:
        // - IP addresses (local Plex servers)
        // - plex.direct domains
        // - Port 32400 (default Plex port)
        let isIPAddress = host.range(of: #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#, options: .regularExpression) != nil
        let isPlexDirect = host.hasSuffix(".plex.direct")
        let isPlexPort = port == 32400

        if isIPAddress || isPlexDirect || isPlexPort {
            // Trust the self-signed certificate
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // Use default handling for other hosts (like plex.tv)
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - API Errors

enum PlexAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case parsingError
    case authenticationFailed
    case notFound
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        case .parsingError:
            return "Failed to parse response"
        case .authenticationFailed:
            return "Authentication failed"
        case .notFound:
            return "Item not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Playback Decision Models

struct PlaybackDecisionContainer: Codable, Sendable {
    let MediaContainer: PlaybackDecision
}

struct PlaybackDecision: Codable, Sendable {
    let size: Int?
    let directPlayDecisionCode: Int?
    let directPlayDecisionText: String?
    let generalDecisionCode: Int?
    let generalDecisionText: String?
    let transcodeDecisionCode: Int?
    let transcodeDecisionText: String?
    
    /// Check if direct play is available
    var canDirectPlay: Bool {
        // Code 1000 = "Direct play OK"
        directPlayDecisionCode == 1000
    }
    
    /// Check if transcoding is required/available
    var requiresTranscode: Bool {
        !canDirectPlay && transcodeDecisionCode != nil
    }
}
