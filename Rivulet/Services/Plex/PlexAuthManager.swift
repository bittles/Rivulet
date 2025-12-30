//
//  PlexAuthManager.swift
//  Rivulet
//
//  Adapted from plex_watchOS AuthManager
//  Handles Plex PIN-based authentication flow for tvOS
//

import Foundation
import SwiftUI
import Combine
import Sentry

// MARK: - Auth State

enum PlexAuthState: Equatable {
    case idle
    case requestingPin
    case waitingForPIN(code: String, pinId: Int)
    case authenticated
    case selectingServer(servers: [PlexDevice])
    case error(message: String)

    static func == (lhs: PlexAuthState, rhs: PlexAuthState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.requestingPin, .requestingPin): return true
        case (.waitingForPIN(let c1, let p1), .waitingForPIN(let c2, let p2)):
            return c1 == c2 && p1 == p2
        case (.authenticated, .authenticated): return true
        case (.selectingServer(let s1), .selectingServer(let s2)):
            return s1.map(\.clientIdentifier) == s2.map(\.clientIdentifier)
        case (.error(let m1), .error(let m2)): return m1 == m2
        default: return false
        }
    }
}

// MARK: - Auth Manager

@MainActor
class PlexAuthManager: ObservableObject {
    static let shared = PlexAuthManager()

    // MARK: - Published State

    @Published var state: PlexAuthState = .idle
    @Published var authToken: String?
    @Published var username: String?
    @Published var selectedServer: PlexDevice?
    @Published var selectedServerURL: String?

    /// Whether we can currently reach the Plex server (separate from authentication)
    @Published var isConnected: Bool = true

    /// Error message when connection fails (displayed to user)
    @Published var connectionError: String?

    // MARK: - Private Properties

    private let networkManager = PlexNetworkManager.shared
    private var pollingTask: Task<Void, Never>?
    private let userDefaults = UserDefaults.standard

    // UserDefaults keys
    private let tokenKey = "plexAuthToken"
    private let usernameKey = "plexUsername"
    private let serverURLKey = "selectedServerURL"
    private let serverNameKey = "selectedServerName"

    // MARK: - Initialization

    private init() {
        // Load saved credentials
        authToken = userDefaults.string(forKey: tokenKey)
        username = userDefaults.string(forKey: usernameKey)
        selectedServerURL = userDefaults.string(forKey: serverURLKey)

        print("🔐 PlexAuthManager: Initialized")
        print("🔐 PlexAuthManager: Token present: \(authToken != nil)")
        print("🔐 PlexAuthManager: Username: \(username ?? "nil")")
        print("🔐 PlexAuthManager: Server URL: \(selectedServerURL ?? "nil")")
        print("🔐 PlexAuthManager: isAuthenticated: \(authToken != nil && selectedServerURL != nil)")

        if authToken != nil {
            state = .authenticated

            // Check if saved URL is a bad Docker/internal address that slipped through
            if let url = selectedServerURL,
               let host = URL(string: url)?.host,
               isDockerOrInternalAddress(host) {
                print("🔐 PlexAuthManager: ⚠️ Saved URL uses Docker/internal address, will re-select on next server fetch")
                // Clear the bad URL - will trigger re-selection
                selectedServerURL = nil
                userDefaults.removeObject(forKey: serverURLKey)
            }
        }
    }

    // MARK: - Public Methods

    /// Start the PIN authentication flow
    func startPINAuthentication() async {
        state = .requestingPin

        do {
            let (pinCode, pinId) = try await networkManager.requestPin()
            state = .waitingForPIN(code: pinCode, pinId: pinId)
            startPollingForAuth(pinId: pinId)
        } catch {
            state = .error(message: "Failed to get PIN: \(error.localizedDescription)")
            scheduleErrorDismissal()

            // Capture PIN request failure to Sentry
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: "plex_auth", key: "component")
                scope.setTag(value: "pin_request", key: "auth_step")
            }
        }
    }

    /// Cancel ongoing authentication
    func cancelAuthentication() {
        pollingTask?.cancel()
        pollingTask = nil
        state = .idle
    }

    /// Select a server from the list
    func selectServer(_ server: PlexDevice) {
        selectedServer = server

        // Find the best working connection
        Task {
            if let workingURL = await findBestConnection(for: server) {
                selectedServerURL = workingURL
                userDefaults.set(selectedServerURL, forKey: serverURLKey)
                userDefaults.set(server.name, forKey: serverNameKey)
                isConnected = true
                connectionError = nil
                state = .authenticated
                print("🔐 PlexAuthManager: Selected connection: \(workingURL)")
            } else {
                isConnected = false
                connectionError = "Could not connect to server. Check your network."
                state = .error(message: "Could not connect to server. Check your network.")
                scheduleErrorDismissal()
            }
        }
    }

    /// Find the best working connection for a server
    private func findBestConnection(for server: PlexDevice) async -> String? {
        let validConnections = server.connections
            .filter { !isDockerOrInternalAddress($0.address) }

        // Sort by preference: local non-relay HTTPS > local non-relay HTTP > remote HTTPS > remote HTTP > relay
        let sortedConnections = validConnections.sorted { conn1, conn2 in
            let score1 = connectionScore(conn1)
            let score2 = connectionScore(conn2)
            return score1 > score2
        }

        print("🔐 PlexAuthManager: Testing \(sortedConnections.count) connections (filtered from \(server.connections.count))")

        for connection in sortedConnections {
            print("🔐 PlexAuthManager: Testing \(connection.uri)...")
            if await testConnection(connection.uri) {
                print("🔐 PlexAuthManager: ✅ Connection works: \(connection.uri)")
                return connection.uri
            } else {
                print("🔐 PlexAuthManager: ❌ Connection failed: \(connection.uri)")
            }
        }

        // If all filtered connections fail, try relay as last resort
        if let relayConnection = server.connections.first(where: { $0.relay }) {
            print("🔐 PlexAuthManager: Trying relay as fallback: \(relayConnection.uri)")
            if await testConnection(relayConnection.uri) {
                return relayConnection.uri
            }
        }

        return nil
    }

    /// Score a connection for sorting (higher = better)
    private func connectionScore(_ connection: PlexConnection) -> Int {
        var score = 0

        // Prefer non-relay (direct connections)
        if !connection.relay { score += 100 }

        // Prefer local connections
        if connection.local { score += 50 }

        // Prefer HTTPS
        if connection.protocolType == "https" { score += 25 }

        // Prefer plex.direct domains (usually more reliable)
        if connection.address.contains(".plex.direct") { score += 10 }

        return score
    }

    /// Check if address is a Docker/internal bridge network
    private func isDockerOrInternalAddress(_ address: String) -> Bool {
        // Docker default bridge networks
        let dockerPrefixes = [
            "172.17.", "172.18.", "172.19.", "172.20.", "172.21.",
            "172.22.", "172.23.", "172.24.", "172.25.", "172.26.",
            "172.27.", "172.28.", "172.29.", "172.30.", "172.31.",
            "10.0.0.", "10.0.1.",  // Common Docker/container networks
        ]

        // Localhost variants (not useful for Apple TV)
        let localhostAddresses = ["127.0.0.1", "localhost", "::1"]

        for prefix in dockerPrefixes {
            if address.hasPrefix(prefix) {
                print("🔐 PlexAuthManager: Skipping Docker/internal address: \(address)")
                return true
            }
        }

        if localhostAddresses.contains(address) {
            print("🔐 PlexAuthManager: Skipping localhost address: \(address)")
            return true
        }

        return false
    }

    /// Test if a connection URL is reachable
    private func testConnection(_ urlString: String) async -> Bool {
        guard let token = authToken,
              let url = URL(string: "\(urlString)/identity") else {
            return false
        }

        do {
            // Quick connectivity test with short timeout
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 5.0
            config.timeoutIntervalForResource = 5.0

            // Use a delegate that trusts self-signed certs for Plex
            let session = URLSession(configuration: config, delegate: PlexCertificateDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }

            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                return (200...299).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            print("🔐 PlexAuthManager: Connection test error: \(error.localizedDescription)")
            return false
        }
    }

    /// Sign out and clear credentials
    func signOut() {
        pollingTask?.cancel()
        pollingTask = nil

        authToken = nil
        username = nil
        selectedServer = nil
        selectedServerURL = nil
        isConnected = true  // Reset to default
        connectionError = nil

        userDefaults.removeObject(forKey: tokenKey)
        userDefaults.removeObject(forKey: usernameKey)
        userDefaults.removeObject(forKey: serverURLKey)
        userDefaults.removeObject(forKey: serverNameKey)

        state = .idle
    }

    /// Reset error state
    func reset() {
        pollingTask?.cancel()
        pollingTask = nil
        state = .idle
    }

    /// Check if currently authenticated (has valid credentials)
    var isAuthenticated: Bool {
        authToken != nil && selectedServerURL != nil
    }

    /// Check if user has saved Plex credentials (for showing cached content even when offline)
    var hasCredentials: Bool {
        authToken != nil && userDefaults.string(forKey: serverURLKey) != nil
    }

    /// Get saved server name
    var savedServerName: String? {
        userDefaults.string(forKey: serverNameKey)
    }

    /// Verify current connection and re-select if needed
    /// Call this on app launch to ensure we have a working server connection
    func verifyAndFixConnection() async {
        guard let token = authToken else { return }

        // If we have no server URL, fetch servers and select one
        if selectedServerURL == nil {
            print("🔐 PlexAuthManager: No server URL saved, fetching servers...")
            do {
                let servers = try await networkManager.getServers(authToken: token)
                if servers.count == 1 {
                    selectServer(servers[0])
                } else if servers.count > 1 {
                    state = .selectingServer(servers: servers)
                }
            } catch {
                print("🔐 PlexAuthManager: Failed to fetch servers: \(error)")
                isConnected = false
                connectionError = "Unable to reach Plex. Check your network connection."

                // Capture server fetch failure to Sentry
                SentrySDK.capture(error: error) { scope in
                    scope.setTag(value: "plex_auth", key: "component")
                    scope.setTag(value: "server_discovery", key: "auth_step")
                }
            }
            return
        }

        // Test current connection
        guard let currentURL = selectedServerURL else { return }
        print("🔐 PlexAuthManager: Verifying current connection: \(currentURL)")

        if await testConnection(currentURL) {
            print("🔐 PlexAuthManager: ✅ Current connection is working")
            isConnected = true
            connectionError = nil
        } else {
            print("🔐 PlexAuthManager: ❌ Current connection failed")
            isConnected = false
            connectionError = "Cannot connect to Plex server"

            // Try to find a better connection without clearing credentials
            // This allows cached content to still be shown
            do {
                let servers = try await networkManager.getServers(authToken: token)
                if let currentServer = servers.first(where: { server in
                    server.connections.contains { $0.uri == currentURL }
                }) ?? servers.first {
                    // Try to find a working connection on this server
                    if let workingURL = await findBestConnection(for: currentServer) {
                        selectedServerURL = workingURL
                        userDefaults.set(selectedServerURL, forKey: serverURLKey)
                        userDefaults.set(currentServer.name, forKey: serverNameKey)
                        isConnected = true
                        connectionError = nil
                        state = .authenticated
                        print("🔐 PlexAuthManager: ✅ Found alternative connection: \(workingURL)")
                    }
                }
            } catch {
                print("🔐 PlexAuthManager: Failed to fetch servers for re-selection: \(error)")
                // Keep existing credentials - just mark as not connected
                // User can still see cached content

                // Capture connection verification failure to Sentry
                SentrySDK.capture(error: error) { scope in
                    scope.setTag(value: "plex_auth", key: "component")
                    scope.setTag(value: "connection_verify", key: "auth_step")
                    scope.setExtra(value: currentURL, key: "failed_url")
                }
            }
        }
    }

    // MARK: - Private Methods

    private func startPollingForAuth(pinId: Int) {
        pollingTask?.cancel()

        pollingTask = Task {
            var attempts = 0
            let maxAttempts = 60 // 5 minutes (5 second intervals)

            while !Task.isCancelled && attempts < maxAttempts {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

                    if let token = try await networkManager.checkPinAuthentication(pinId: pinId) {
                        // Successfully authenticated!
                        await handleSuccessfulAuth(token: token)
                        return
                    }

                    attempts += 1
                } catch {
                    if !Task.isCancelled {
                        state = .error(message: "Authentication check failed: \(error.localizedDescription)")
                        scheduleErrorDismissal()
                    }
                    return
                }
            }

            if !Task.isCancelled {
                state = .error(message: "PIN expired. Please try again.")
                scheduleErrorDismissal()
            }
        }
    }

    private func handleSuccessfulAuth(token: String) async {
        authToken = token
        userDefaults.set(token, forKey: tokenKey)

        // Fetch user info
        await fetchUserInfo()

        // Fetch available servers
        do {
            let servers = try await networkManager.getServers(authToken: token)

            if servers.isEmpty {
                state = .error(message: "No Plex servers found on your account")
                scheduleErrorDismissal()
            } else if servers.count == 1 {
                // Auto-select if only one server
                selectServer(servers[0])
            } else {
                // Show server selection
                state = .selectingServer(servers: servers)
            }
        } catch {
            state = .error(message: "Failed to fetch servers: \(error.localizedDescription)")
            scheduleErrorDismissal()
        }
    }

    private func fetchUserInfo() async {
        guard let token = authToken else { return }

        do {
            let url = URL(string: "https://plex.tv/api/v2/user")!
            let data = try await networkManager.requestData(
                url,
                headers: [
                    "X-Plex-Token": token,
                    "X-Plex-Client-Identifier": PlexAPI.clientIdentifier,
                    "Accept": "application/json"
                ]
            )

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["username"] as? String ?? json["friendlyName"] as? String {
                username = name
                userDefaults.set(name, forKey: usernameKey)
            }
        } catch {
            // Non-critical error, just log it
            print("Failed to fetch user info: \(error)")
        }
    }

    private func scheduleErrorDismissal() {
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if case .error = state {
                state = .idle
            }
        }
    }
}

// MARK: - Auth URL Helper

extension PlexAuthManager {
    /// Get the URL for users to authenticate via browser
    var authURL: URL? {
        guard case .waitingForPIN(let code, _) = state else { return nil }

        var components = URLComponents(string: "https://app.plex.tv/auth")!
        components.fragment = "?clientID=\(PlexAPI.clientIdentifier)&code=\(code)&context[device][product]=Rivulet"
        return components.url
    }
}

// MARK: - Certificate Delegate for Connection Testing

/// URLSession delegate that trusts self-signed certificates for Plex servers
class PlexCertificateDelegate: NSObject, URLSessionDelegate {
    func urlSession(
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
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
