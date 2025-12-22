//
//  PlexLiveTVProvider.swift
//  Rivulet
//
//  LiveTVProvider implementation for Plex Live TV
//

import Foundation

/// LiveTVProvider implementation for Plex Live TV
actor PlexLiveTVProvider: LiveTVProvider {

    // MARK: - Properties

    let sourceType: LiveTVSourceType = .plex
    let sourceId: String
    let displayName: String

    private let serverURL: String
    private let authToken: String
    private let networkManager = PlexNetworkManager.shared

    // Cached data
    private var cachedChannels: [UnifiedChannel] = []
    private var cachedEPG: [String: [UnifiedProgram]] = [:]
    private var lastChannelFetch: Date?
    private var lastEPGFetch: Date?
    private var capabilities: PlexLiveTVCapabilities?

    // Cache duration
    private let channelCacheDuration: TimeInterval = 300  // 5 minutes
    private let epgCacheDuration: TimeInterval = 1800     // 30 minutes

    // MARK: - Initialization

    init(serverURL: String, authToken: String, serverName: String) {
        self.serverURL = serverURL
        self.authToken = authToken
        self.sourceId = "plex:\(serverURL)"
        self.displayName = "\(serverName) Live TV"
    }

    // MARK: - LiveTVProvider Protocol

    var isConnected: Bool {
        get async {
            // Check if Plex Live TV is available
            do {
                if let caps = capabilities {
                    return caps.liveTVEnabled
                }
                let caps = try await networkManager.getLiveTVCapabilities(
                    serverURL: serverURL,
                    authToken: authToken
                )
                return caps.liveTVEnabled
            } catch {
                return false
            }
        }
    }

    func fetchChannels() async throws -> [UnifiedChannel] {
        // Return cached if still valid
        if let lastFetch = lastChannelFetch,
           Date().timeIntervalSince(lastFetch) < channelCacheDuration,
           !cachedChannels.isEmpty {
            print("📺 PlexLiveTVProvider: Returning \(cachedChannels.count) cached channels")
            return cachedChannels
        }

        return try await refreshChannels()
    }

    func refreshChannels() async throws -> [UnifiedChannel] {
        print("📺 PlexLiveTVProvider: Fetching channels from Plex Live TV")

        // First check capabilities
        let caps = try await networkManager.getLiveTVCapabilities(
            serverURL: serverURL,
            authToken: authToken
        )
        capabilities = caps

        guard caps.liveTVEnabled else {
            throw LiveTVProviderError.notConnected
        }

        // Fetch channels
        let plexChannels = try await networkManager.getLiveTVChannels(
            serverURL: serverURL,
            authToken: authToken
        )

        print("📺 PlexLiveTVProvider: ✅ Fetched \(plexChannels.count) channels")

        // Convert to UnifiedChannel
        let channels = plexChannels.map { plexChannel in
            plexChannel.toUnifiedChannel(
                sourceId: sourceId,
                serverURL: serverURL,
                authToken: authToken
            )
        }

        // Update cache
        cachedChannels = channels
        lastChannelFetch = Date()

        return channels
    }

    func fetchEPG(
        for channels: [UnifiedChannel],
        startDate: Date,
        endDate: Date
    ) async throws -> [String: [UnifiedProgram]] {
        // Return cached if still valid and covers the requested range
        if let lastFetch = lastEPGFetch,
           Date().timeIntervalSince(lastFetch) < epgCacheDuration,
           !cachedEPG.isEmpty {
            print("📺 PlexLiveTVProvider: Returning cached EPG")
            return filterEPG(cachedEPG, channels: channels, startDate: startDate, endDate: endDate)
        }

        print("📺 PlexLiveTVProvider: Fetching EPG from Plex")

        // Build channel ID list for filtering
        let channelRatingKeys = channels.compactMap { channel -> String? in
            // Extract the rating key from the unified ID (plex:serverURL:ratingKey)
            let components = channel.id.split(separator: ":")
            return components.count >= 3 ? String(components.last!) : nil
        }

        // Fetch guide data
        let guideChannels = try await networkManager.getLiveTVGuide(
            serverURL: serverURL,
            authToken: authToken,
            channelIds: channelRatingKeys.isEmpty ? nil : channelRatingKeys,
            startTime: startDate,
            endTime: endDate
        )

        print("📺 PlexLiveTVProvider: ✅ Fetched EPG for \(guideChannels.count) channels")

        // Build unified channel ID lookup
        let ratingKeyToUnifiedId = Dictionary(
            uniqueKeysWithValues: channels.map { channel -> (String, String) in
                let components = channel.id.split(separator: ":")
                let ratingKey = components.count >= 3 ? String(components.last!) : channel.id
                return (ratingKey, channel.id)
            }
        )

        // Convert to UnifiedProgram
        var unifiedEPG: [String: [UnifiedProgram]] = [:]

        for guideChannel in guideChannels {
            guard let ratingKey = guideChannel.ratingKey,
                  let unifiedChannelId = ratingKeyToUnifiedId[ratingKey],
                  let programs = guideChannel.Metadata else {
                continue
            }

            let unifiedPrograms = programs.compactMap { plexProgram in
                plexProgram.toUnifiedProgram(unifiedChannelId: unifiedChannelId)
            }

            if !unifiedPrograms.isEmpty {
                unifiedEPG[unifiedChannelId] = unifiedPrograms
            }
        }

        // Update cache
        cachedEPG = unifiedEPG
        lastEPGFetch = Date()

        return unifiedEPG
    }

    func getCurrentProgram(for channel: UnifiedChannel) async -> UnifiedProgram? {
        guard let programs = cachedEPG[channel.id] else {
            return nil
        }

        let now = Date()
        return programs.first { program in
            program.startTime <= now && program.endTime > now
        }
    }

    nonisolated func buildStreamURL(for channel: UnifiedChannel) -> URL? {
        // The stream URL is already built into the channel
        return channel.streamURL
    }

    // MARK: - Private Methods

    private func filterEPG(
        _ epg: [String: [UnifiedProgram]],
        channels: [UnifiedChannel],
        startDate: Date,
        endDate: Date
    ) -> [String: [UnifiedProgram]] {
        let channelIds = Set(channels.map { $0.id })

        var filtered: [String: [UnifiedProgram]] = [:]

        for (channelId, programs) in epg {
            guard channelIds.contains(channelId) else { continue }

            let filteredPrograms = programs.filter { program in
                program.endTime > startDate && program.startTime < endDate
            }

            if !filteredPrograms.isEmpty {
                filtered[channelId] = filteredPrograms
            }
        }

        return filtered
    }

    // MARK: - Cache Management

    func clearCache() {
        cachedChannels = []
        cachedEPG = [:]
        lastChannelFetch = nil
        lastEPGFetch = nil
        capabilities = nil
    }

    // MARK: - Capability Check

    /// Check if Plex Live TV is available (call this before adding as a source)
    static func checkAvailability(serverURL: String, authToken: String) async -> Bool {
        do {
            let caps = try await PlexNetworkManager.shared.getLiveTVCapabilities(
                serverURL: serverURL,
                authToken: authToken
            )
            return caps.liveTVEnabled
        } catch {
            return false
        }
    }
}
