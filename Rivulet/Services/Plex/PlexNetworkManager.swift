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

    /// Get home screen hubs
    func getHubs(serverURL: String, authToken: String) async throws -> [PlexHub] {
        guard let url = URL(string: "\(serverURL)/hubs") else {
            throw PlexAPIError.invalidURL
        }

        let container: PlexMediaContainerWrapper = try await request(
            url,
            headers: plexHeaders(authToken: authToken)
        )

        return container.MediaContainer.Hub ?? []
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

        _ = try await requestData(url, headers: plexHeaders(authToken: authToken))
    }

    // MARK: - Streaming URLs

    /// Build HLS streaming URL with H264 transcoding
    func buildStreamURL(
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

            // Media reference
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "offset", value: "\(offsetMs / 1000)"),

            // Protocol and transcode settings
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "directPlay", value: "0"),  // Force transcode
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "directStreamAudio", value: "1"),

            // Force H264 to avoid HEVC buffering issues on Apple TV
            URLQueryItem(name: "videoCodec", value: "h264"),
            URLQueryItem(name: "videoResolution", value: "1920x1080"),
            URLQueryItem(name: "maxVideoBitrate", value: "20000"),
            URLQueryItem(name: "videoQuality", value: "100"),
            URLQueryItem(name: "h264Level", value: "42"),
            URLQueryItem(name: "h264Profile", value: "high"),

            // Audio
            URLQueryItem(name: "audioCodec", value: "aac,ac3,eac3"),
            URLQueryItem(name: "audioBoost", value: "100"),

            // Context
            URLQueryItem(name: "context", value: "streaming"),
            URLQueryItem(name: "location", value: "lan"),

            // Session
            URLQueryItem(name: "session", value: sessionId)
        ]

        return components.url
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
        sectionId: String? = nil
    ) async throws -> [PlexMetadata] {
        var urlString = "\(serverURL)/search"
        if let section = sectionId {
            urlString = "\(serverURL)/library/sections/\(section)/search"
        }

        guard var components = URLComponents(string: urlString) else {
            throw PlexAPIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "query", value: query)
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
