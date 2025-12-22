//
//  LiveTVDataStore.swift
//  Rivulet
//
//  Central state management for Live TV channels and EPG across all sources
//

import Foundation
import Combine

@MainActor
class LiveTVDataStore: ObservableObject {
    static let shared = LiveTVDataStore()

    // MARK: - Published State

    /// All channels from all sources, merged and sorted
    @Published var channels: [UnifiedChannel] = []

    /// Current EPG data (channelId -> programs)
    @Published var epg: [String: [UnifiedProgram]] = [:]

    /// Favorite channel IDs
    @Published var favoriteIds: Set<String> = [] {
        didSet {
            saveFavorites()
        }
    }

    /// Loading states
    @Published var isLoadingChannels = false
    @Published var isLoadingEPG = false

    /// Error states
    @Published var channelsError: String?
    @Published var epgError: String?

    /// Active provider configurations
    @Published private(set) var sources: [LiveTVSourceInfo] = []

    // MARK: - Private Properties

    private var providers: [String: any LiveTVProvider] = [:]
    private var channelLoadTask: Task<Void, Never>?
    private var epgLoadTask: Task<Void, Never>?

    private let userDefaults = UserDefaults.standard
    private let favoritesKey = "liveTVFavoriteChannelIds"

    // MARK: - Source Info

    struct LiveTVSourceInfo: Identifiable, Sendable {
        let id: String
        let sourceType: LiveTVSourceType
        let displayName: String
        let channelCount: Int
        let isConnected: Bool
        let lastSync: Date?
    }

    // MARK: - Computed Properties

    /// Channels filtered to favorites only
    var favoriteChannels: [UnifiedChannel] {
        channels.filter { favoriteIds.contains($0.id) }
    }

    /// Channels grouped by category/group
    var channelsByGroup: [String: [UnifiedChannel]] {
        var groups: [String: [UnifiedChannel]] = [:]
        for channel in channels {
            let group = channel.groupTitle ?? "Other"
            if groups[group] == nil {
                groups[group] = []
            }
            groups[group]?.append(channel)
        }
        return groups
    }

    /// Available group names, sorted
    var availableGroups: [String] {
        channelsByGroup.keys.sorted()
    }

    /// Check if any Live TV source is configured
    var hasConfiguredSources: Bool {
        !providers.isEmpty
    }

    // MARK: - Initialization

    private init() {
        loadFavorites()
        print("📺 LiveTVDataStore: Initialized")
    }

    // MARK: - Source Management

    /// Add a Dispatcharr source
    func addDispatcharrSource(baseURL: URL, name: String) async {
        let sourceId = "dispatcharr:\(baseURL.absoluteString)"
        let provider = IPTVProvider(
            dispatcharrURL: baseURL,
            sourceId: sourceId,
            displayName: name
        )
        providers[sourceId] = provider
        await updateSourceInfo()
        print("📺 LiveTVDataStore: Added Dispatcharr source '\(name)'")
    }

    /// Add a generic M3U source
    func addM3USource(m3uURL: URL, epgURL: URL?, name: String) async {
        let sourceId = "m3u:\(m3uURL.absoluteString)"
        let provider = IPTVProvider(
            m3uURL: m3uURL,
            epgURL: epgURL,
            sourceId: sourceId,
            displayName: name
        )
        providers[sourceId] = provider
        await updateSourceInfo()
        print("📺 LiveTVDataStore: Added M3U source '\(name)'")
    }

    /// Add a Plex Live TV source
    func addPlexSource(provider: any LiveTVProvider) async {
        providers[provider.sourceId] = provider
        await updateSourceInfo()
        print("📺 LiveTVDataStore: Added Plex Live TV source")
    }

    /// Remove a source by ID
    func removeSource(id: String) async {
        providers.removeValue(forKey: id)
        await updateSourceInfo()

        // Remove channels from this source
        channels.removeAll { $0.sourceId == id }

        // Remove EPG for these channels
        let channelIds = Set(channels.filter { $0.sourceId == id }.map { $0.id })
        for channelId in channelIds {
            epg.removeValue(forKey: channelId)
        }

        print("📺 LiveTVDataStore: Removed source '\(id)'")
    }

    /// Update source info for UI
    private func updateSourceInfo() async {
        var infos: [LiveTVSourceInfo] = []

        for (id, provider) in providers {
            let isConnected = await provider.isConnected
            let channelCount = channels.filter { $0.sourceId == id }.count

            infos.append(LiveTVSourceInfo(
                id: id,
                sourceType: provider.sourceType,
                displayName: provider.displayName,
                channelCount: channelCount,
                isConnected: isConnected,
                lastSync: nil  // TODO: Track last sync time
            ))
        }

        sources = infos.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Channel Loading

    /// Load channels from all sources
    func loadChannels() async {
        guard !providers.isEmpty else {
            print("📺 LiveTVDataStore: No sources configured")
            return
        }

        // Cancel existing task if any
        channelLoadTask?.cancel()

        isLoadingChannels = true
        channelsError = nil

        channelLoadTask = Task {
            var allChannels: [UnifiedChannel] = []
            var errors: [String] = []

            // Fetch from all providers in parallel
            await withTaskGroup(of: (String, Result<[UnifiedChannel], Error>).self) { group in
                for (id, provider) in providers {
                    group.addTask {
                        do {
                            let channels = try await provider.fetchChannels()
                            return (id, .success(channels))
                        } catch {
                            return (id, .failure(error))
                        }
                    }
                }

                for await (sourceId, result) in group {
                    switch result {
                    case .success(let channels):
                        allChannels.append(contentsOf: channels)
                        print("📺 LiveTVDataStore: Loaded \(channels.count) channels from \(sourceId)")
                    case .failure(let error):
                        errors.append("\(sourceId): \(error.localizedDescription)")
                        print("📺 LiveTVDataStore: ❌ Failed to load from \(sourceId): \(error)")
                    }
                }
            }

            // Sort channels by number, then name
            allChannels.sort { c1, c2 in
                if let n1 = c1.channelNumber, let n2 = c2.channelNumber {
                    return n1 < n2
                } else if c1.channelNumber != nil {
                    return true
                } else if c2.channelNumber != nil {
                    return false
                } else {
                    return c1.name < c2.name
                }
            }

            await MainActor.run {
                self.channels = allChannels
                self.isLoadingChannels = false
                if !errors.isEmpty {
                    self.channelsError = errors.joined(separator: "\n")
                }
            }

            await updateSourceInfo()
        }

        await channelLoadTask?.value
    }

    /// Refresh channels from all sources
    func refreshChannels() async {
        guard !providers.isEmpty else { return }

        isLoadingChannels = true
        channelsError = nil

        var allChannels: [UnifiedChannel] = []
        var errors: [String] = []

        // Refresh from all providers in parallel
        await withTaskGroup(of: (String, Result<[UnifiedChannel], Error>).self) { group in
            for (id, provider) in providers {
                group.addTask {
                    do {
                        let channels = try await provider.refreshChannels()
                        return (id, .success(channels))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }

            for await (sourceId, result) in group {
                switch result {
                case .success(let channels):
                    allChannels.append(contentsOf: channels)
                case .failure(let error):
                    errors.append("\(sourceId): \(error.localizedDescription)")
                }
            }
        }

        // Sort channels
        allChannels.sort { c1, c2 in
            if let n1 = c1.channelNumber, let n2 = c2.channelNumber {
                return n1 < n2
            } else if c1.channelNumber != nil {
                return true
            } else if c2.channelNumber != nil {
                return false
            } else {
                return c1.name < c2.name
            }
        }

        channels = allChannels
        isLoadingChannels = false
        if !errors.isEmpty {
            channelsError = errors.joined(separator: "\n")
        }

        await updateSourceInfo()
    }

    // MARK: - EPG Loading

    /// Load EPG for the specified time range
    func loadEPG(startDate: Date = Date(), hours: Int = 24) async {
        guard !providers.isEmpty, !channels.isEmpty else {
            print("📺 LiveTVDataStore: No sources or channels for EPG")
            return
        }

        epgLoadTask?.cancel()

        isLoadingEPG = true
        epgError = nil

        let endDate = Calendar.current.date(byAdding: .hour, value: hours, to: startDate) ?? startDate

        epgLoadTask = Task {
            var allEPG: [String: [UnifiedProgram]] = [:]
            var errors: [String] = []

            // Group channels by source
            let channelsBySource = Dictionary(grouping: channels, by: { $0.sourceId })

            // Fetch EPG from each provider
            await withTaskGroup(of: (String, Result<[String: [UnifiedProgram]], Error>).self) { group in
                for (sourceId, sourceChannels) in channelsBySource {
                    guard let provider = providers[sourceId] else { continue }

                    group.addTask {
                        do {
                            let epg = try await provider.fetchEPG(
                                for: sourceChannels,
                                startDate: startDate,
                                endDate: endDate
                            )
                            return (sourceId, .success(epg))
                        } catch {
                            return (sourceId, .failure(error))
                        }
                    }
                }

                for await (sourceId, result) in group {
                    switch result {
                    case .success(let epg):
                        for (channelId, programs) in epg {
                            allEPG[channelId] = programs
                        }
                        print("📺 LiveTVDataStore: Loaded EPG for \(epg.count) channels from \(sourceId)")
                    case .failure(let error):
                        // EPG errors are not critical, just log them
                        errors.append("\(sourceId): \(error.localizedDescription)")
                        print("📺 LiveTVDataStore: ⚠️ EPG load failed for \(sourceId): \(error)")
                    }
                }
            }

            await MainActor.run {
                self.epg = allEPG
                self.isLoadingEPG = false
                if !errors.isEmpty {
                    self.epgError = errors.joined(separator: "\n")
                }
            }
        }

        await epgLoadTask?.value
    }

    // MARK: - Program Helpers

    /// Get the current program for a channel
    func getCurrentProgram(for channel: UnifiedChannel) -> UnifiedProgram? {
        guard let programs = epg[channel.id] else { return nil }
        let now = Date()
        return programs.first { $0.startTime <= now && $0.endTime > now }
    }

    /// Get the next program for a channel
    func getNextProgram(for channel: UnifiedChannel) -> UnifiedProgram? {
        guard let programs = epg[channel.id] else { return nil }
        let now = Date()
        return programs.first { $0.startTime > now }
    }

    /// Get programs for a channel within a time range
    func getPrograms(for channel: UnifiedChannel, startDate: Date, endDate: Date) -> [UnifiedProgram] {
        guard let programs = epg[channel.id] else { return [] }
        return programs.filter { $0.endTime > startDate && $0.startTime < endDate }
    }

    // MARK: - Favorites

    func toggleFavorite(_ channel: UnifiedChannel) {
        if favoriteIds.contains(channel.id) {
            favoriteIds.remove(channel.id)
        } else {
            favoriteIds.insert(channel.id)
        }
    }

    func isFavorite(_ channel: UnifiedChannel) -> Bool {
        favoriteIds.contains(channel.id)
    }

    private func loadFavorites() {
        if let saved = userDefaults.array(forKey: favoritesKey) as? [String] {
            favoriteIds = Set(saved)
        }
    }

    private func saveFavorites() {
        userDefaults.set(Array(favoriteIds), forKey: favoritesKey)
    }

    // MARK: - Stream URL

    /// Build the stream URL for a channel
    func buildStreamURL(for channel: UnifiedChannel) -> URL? {
        guard let provider = providers[channel.sourceId] else {
            // Fallback to channel's stream URL
            return channel.streamURL
        }
        return provider.buildStreamURL(for: channel)
    }

    // MARK: - Reset

    func reset() {
        channelLoadTask?.cancel()
        epgLoadTask?.cancel()
        providers.removeAll()
        channels = []
        epg = [:]
        sources = []
        channelsError = nil
        epgError = nil
        isLoadingChannels = false
        isLoadingEPG = false
        print("📺 LiveTVDataStore: Reset all data")
    }
}
