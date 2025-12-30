# Multi-Account Plex Support

A technical guide for implementing support for multiple Plex accounts with libraries from all accounts visible in the sidebar.

---

## Feature Overview

Allow users to connect multiple Plex accounts simultaneously:
- Libraries from any account visible in the sidebar (grouped by account)
- Home screen defaults to one "primary" account
- Seamless browsing across accounts

---

## Current Architecture

### What's Already Multi-Account Ready
- **PlexNetworkManager** - All methods take `serverURL` and `authToken` as parameters (no global state)
- **SwiftData models** - `PlexServer`, `ServerConfiguration` exist (but currently unused)

### What Needs Changes

| Component | Current State | Problem |
|-----------|---------------|---------|
| `PlexAuthManager` | Singleton, stores single account in UserDefaults | Only one `authToken`/`selectedServerURL` |
| `PlexDataStore` | Singleton, single `libraries` array | Can't merge libraries from multiple accounts |
| `PlexLibrary.id` | Uses `key` ("1", "2", etc.) | Not unique across servers (collision risk) |
| `LibrarySettingsManager` | Uses plain library keys | Settings would conflict between accounts |
| `CacheManager` | Files like `movies_1.json` | Would overwrite across accounts |
| `TVSidebarView` | One server section header | No multi-account grouping |

---

## Implementation Plan

### Phase 1: Data Model Updates

#### 1.1 Create PlexAccount Model

```swift
// New: Services/Plex/PlexAccount.swift

import Foundation

struct PlexAccount: Codable, Identifiable, Equatable {
    let id: UUID
    var username: String
    var authToken: String
    var serverURL: String
    var serverName: String
    var machineIdentifier: String
    var isPrimary: Bool          // Used for home screen hubs
    var addedAt: Date

    init(
        id: UUID = UUID(),
        username: String,
        authToken: String,
        serverURL: String,
        serverName: String,
        machineIdentifier: String,
        isPrimary: Bool = false,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.authToken = authToken
        self.serverURL = serverURL
        self.serverName = serverName
        self.machineIdentifier = machineIdentifier
        self.isPrimary = isPrimary
        self.addedAt = addedAt
    }
}
```

#### 1.2 Extend PlexLibrary with Account Context

```swift
// Modify: Models/Plex/PlexModels.swift

struct PlexLibrary: Codable, Identifiable, Sendable {
    // Existing fields...
    let key: String
    let type: String
    let title: String
    // etc...

    // NEW: Account context (set after fetch, not from Plex API)
    var accountId: UUID?
    var serverURL: String?

    // NEW: Compound identifier unique across all accounts
    var uniqueId: String {
        guard let accountId else { return key }
        return "\(accountId.uuidString).\(key)"
    }

    // Existing computed properties...
    var id: String { key }
    var isVideoLibrary: Bool { type == "movie" || type == "show" }
    var isMusicLibrary: Bool { type == "artist" }
}
```

### Phase 2: Account Management

#### 2.1 Create PlexAccountManager

```swift
// New: Services/Plex/PlexAccountManager.swift

import Foundation
import Combine

@MainActor
class PlexAccountManager: ObservableObject {
    static let shared = PlexAccountManager()

    @Published private(set) var accounts: [PlexAccount] = []
    @Published private(set) var primaryAccount: PlexAccount?

    private let storageKey = "plexAccounts"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        loadAccounts()
    }

    // MARK: - Account Operations

    func addAccount(_ account: PlexAccount) {
        // Prevent duplicates by machineIdentifier
        guard !accounts.contains(where: { $0.machineIdentifier == account.machineIdentifier }) else {
            // Update existing account instead
            updateAccount(account)
            return
        }

        var newAccount = account
        // First account is automatically primary
        if accounts.isEmpty {
            newAccount.isPrimary = true
        }

        accounts.append(newAccount)
        if newAccount.isPrimary {
            primaryAccount = newAccount
        }
        saveAccounts()
    }

    func removeAccount(id: UUID) {
        accounts.removeAll { $0.id == id }

        // If we removed the primary, assign new primary
        if primaryAccount?.id == id {
            primaryAccount = accounts.first
            if var first = accounts.first {
                first.isPrimary = true
                accounts[0] = first
            }
        }
        saveAccounts()
    }

    func updateAccount(_ account: PlexAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            if account.isPrimary {
                primaryAccount = account
            }
            saveAccounts()
        }
    }

    func setPrimaryAccount(id: UUID) {
        for i in accounts.indices {
            accounts[i].isPrimary = (accounts[i].id == id)
        }
        primaryAccount = accounts.first { $0.id == id }
        saveAccounts()
    }

    func getAccount(id: UUID) -> PlexAccount? {
        accounts.first { $0.id == id }
    }

    func getAccount(for serverURL: String) -> PlexAccount? {
        accounts.first { $0.serverURL == serverURL }
    }

    func getAccount(for machineIdentifier: String) -> PlexAccount? {
        accounts.first { $0.machineIdentifier == machineIdentifier }
    }

    // MARK: - Persistence

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([PlexAccount].self, from: data) else {
            return
        }
        accounts = decoded
        primaryAccount = accounts.first { $0.isPrimary } ?? accounts.first
    }

    private func saveAccounts() {
        guard let data = try? encoder.encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Migration

    /// Migrate existing single-account credentials to multi-account system
    func migrateFromLegacyAuth() {
        guard accounts.isEmpty else { return }  // Already migrated

        // Check for existing credentials in old UserDefaults keys
        let token = UserDefaults.standard.string(forKey: "plexAuthToken")
        let serverURL = UserDefaults.standard.string(forKey: "selectedServerURL")
        let serverName = UserDefaults.standard.string(forKey: "selectedServerName")
        let username = UserDefaults.standard.string(forKey: "plexUsername")

        guard let token, let serverURL, !token.isEmpty, !serverURL.isEmpty else {
            return
        }

        let account = PlexAccount(
            username: username ?? "Plex User",
            authToken: token,
            serverURL: serverURL,
            serverName: serverName ?? "Plex Server",
            machineIdentifier: "legacy-\(UUID().uuidString)",
            isPrimary: true
        )

        addAccount(account)
        print("📦 Migrated legacy Plex credentials to multi-account system")
    }
}
```

#### 2.2 Update PlexAuthManager

Keep `PlexAuthManager` for the **active login flow only** (PIN-based auth). After authentication completes, hand off to `PlexAccountManager`:

```swift
// Modify: Services/Plex/PlexAuthManager.swift

// In completeAuthentication() or wherever auth flow finishes:
func completeAuthentication(token: String, server: PlexDevice) {
    // Create account from auth result
    let account = PlexAccount(
        username: self.username ?? "Plex User",
        authToken: token,
        serverURL: server.connection?.uri ?? "",
        serverName: server.name,
        machineIdentifier: server.clientIdentifier,
        isPrimary: PlexAccountManager.shared.accounts.isEmpty
    )

    // Add to account manager (handles persistence)
    PlexAccountManager.shared.addAccount(account)

    // Clear transient auth state
    self.authState = .idle

    // Legacy: Keep selectedServerURL for backward compatibility during transition
    self.selectedServerURL = server.connection?.uri
}
```

### Phase 3: Multi-Account Data Store

#### 3.1 Update PlexDataStore

```swift
// Modify: Services/Plex/PlexDataStore.swift

class PlexDataStore: ObservableObject {
    static let shared = PlexDataStore()

    // NEW: Libraries grouped by account
    @Published var librariesByAccount: [UUID: [PlexLibrary]] = [:]

    // Existing: Hubs still from primary account
    @Published var hubs: [PlexHub] = []

    // Loading state per account
    @Published var loadingAccounts: Set<UUID> = []

    private let networkManager = PlexNetworkManager.shared
    private let accountManager = PlexAccountManager.shared
    private let librarySettings = LibrarySettingsManager.shared

    // MARK: - Computed Properties

    /// All libraries from all accounts, flattened
    var allLibraries: [PlexLibrary] {
        librariesByAccount.values.flatMap { $0 }
    }

    /// Visible libraries (respecting user settings)
    var visibleLibraries: [PlexLibrary] {
        librarySettings.filterVisibleLibraries(allLibraries)
    }

    /// Libraries for a specific account
    func libraries(for accountId: UUID) -> [PlexLibrary] {
        librariesByAccount[accountId] ?? []
    }

    /// Visible libraries for a specific account
    func visibleLibraries(for accountId: UUID) -> [PlexLibrary] {
        librarySettings.filterVisibleLibraries(libraries(for: accountId))
    }

    // MARK: - Loading

    /// Load libraries for a single account
    func loadLibraries(for account: PlexAccount) async {
        guard !loadingAccounts.contains(account.id) else { return }

        await MainActor.run { loadingAccounts.insert(account.id) }

        do {
            let libs = try await networkManager.getLibraries(
                serverURL: account.serverURL,
                authToken: account.authToken
            )

            // Tag each library with account context
            let taggedLibs = libs.map { lib -> PlexLibrary in
                var tagged = lib
                tagged.accountId = account.id
                tagged.serverURL = account.serverURL
                return tagged
            }

            await MainActor.run {
                librariesByAccount[account.id] = taggedLibs
                loadingAccounts.remove(account.id)
            }
        } catch {
            await MainActor.run { loadingAccounts.remove(account.id) }
            print("❌ Failed to load libraries for \(account.serverName): \(error)")
        }
    }

    /// Load libraries for all accounts
    func loadAllAccounts() async {
        await withTaskGroup(of: Void.self) { group in
            for account in accountManager.accounts {
                group.addTask {
                    await self.loadLibraries(for: account)
                }
            }
        }
    }

    /// Load hubs from primary account
    func loadHubsIfNeeded() async {
        guard let primary = accountManager.primaryAccount else { return }
        // Existing hub loading logic, using primary.serverURL and primary.authToken
    }
}
```

### Phase 4: Settings & Cache Updates

#### 4.1 Update LibrarySettingsManager

Use compound keys (`accountId.libraryKey`) to avoid conflicts:

```swift
// Modify: Services/Plex/LibrarySettingsManager.swift

func isLibraryVisible(_ library: PlexLibrary) -> Bool {
    !hiddenLibraryKeys.contains(library.uniqueId)
}

func toggleVisibility(for library: PlexLibrary) {
    let key = library.uniqueId
    if hiddenLibraryKeys.contains(key) {
        hiddenLibraryKeys.remove(key)
    } else {
        hiddenLibraryKeys.insert(key)
    }
}

func filterVisibleLibraries(_ libraries: [PlexLibrary]) -> [PlexLibrary] {
    libraries.filter { isLibraryVisible($0) }
}

// Migration helper
func migrateKeysForAccount(_ accountId: UUID, libraryKeys: [String]) {
    // Convert old keys like "1", "2" to "accountId.1", "accountId.2"
    var newHidden = Set<String>()
    for oldKey in hiddenLibraryKeys {
        if libraryKeys.contains(oldKey) {
            newHidden.insert("\(accountId.uuidString).\(oldKey)")
        }
    }
    hiddenLibraryKeys = newHidden
}
```

#### 4.2 Update CacheManager

Namespace cache files by account to prevent collisions:

```swift
// Modify: Services/Cache/CacheManager.swift

func cacheLibraries(_ libraries: [PlexLibrary], for accountId: UUID) {
    let fileName = "libraries_\(accountId.uuidString).json"
    cacheData(libraries, fileName: fileName)
}

func getCachedLibraries(for accountId: UUID) -> [PlexLibrary]? {
    let fileName = "libraries_\(accountId.uuidString).json"
    return decodedCache(for: fileName, as: [PlexLibrary].self)
}

func cacheMovies(_ movies: [PlexMetadata], forLibrary library: PlexLibrary) {
    guard let accountId = library.accountId else { return }
    let fileName = "movies_\(accountId.uuidString)_\(library.key).json"
    cacheData(movies, fileName: fileName)
}

func getCachedMovies(forLibrary library: PlexLibrary) -> [PlexMetadata]? {
    guard let accountId = library.accountId else { return nil }
    let fileName = "movies_\(accountId.uuidString)_\(library.key).json"
    return decodedCache(for: fileName, as: [PlexMetadata].self)
}
```

### Phase 5: UI Updates

#### 5.1 Update TVSidebarView

Libraries grouped by account - each account gets its own section header:

```swift
// Modify: Views/TVNavigation/TVSidebarView.swift

struct TVSidebarView: View {
    @StateObject private var accountManager = PlexAccountManager.shared
    @StateObject private var dataStore = PlexDataStore.shared
    // ... other properties

    var body: some View {
        // ... existing structure

        // Libraries section - now grouped by account
        ForEach(accountManager.accounts) { account in
            if !dataStore.visibleLibraries(for: account.id).isEmpty {
                sectionHeader(account.serverName.uppercased())

                ForEach(dataStore.visibleLibraries(for: account.id), id: \.uniqueId) { library in
                    FocusableSidebarRow(
                        id: library.uniqueId,
                        icon: iconForLibrary(library),
                        title: library.title,
                        isSelected: selectedLibraryKey == library.uniqueId,
                        onSelect: { navigateToLibrary(library) },
                        focusedItem: $sidebarFocusedItem
                    )
                }
            }
        }

        // ... rest of sidebar
    }

    private func navigateToLibrary(_ library: PlexLibrary) {
        selectedLibraryKey = library.uniqueId
        selectedLibrary = library  // Store full library for context
        selectedDestination = .home
    }
}
```

#### 5.2 Update PlexLibraryView

Use library's embedded account context for API calls:

```swift
// Modify: Views/Plex/PlexLibraryView.swift

struct PlexLibraryView: View {
    let library: PlexLibrary

    // Derive credentials from library's account context
    private var serverURL: String {
        library.serverURL ?? ""
    }

    private var authToken: String {
        guard let accountId = library.accountId else { return "" }
        return PlexAccountManager.shared.getAccount(id: accountId)?.authToken ?? ""
    }

    var body: some View {
        // Use serverURL and authToken for all network calls
    }
}
```

#### 5.3 Update PlexDetailView

Similarly, pass account context through for API calls:

```swift
// Modify: Views/Plex/PlexDetailView.swift

struct PlexDetailView: View {
    let item: PlexMetadata

    // Get credentials from item's library context
    private var serverURL: String {
        // Item should have serverURL set when created
        item.serverURL ?? PlexAccountManager.shared.primaryAccount?.serverURL ?? ""
    }

    private var authToken: String {
        // Item should have accountId set when created
        if let accountId = item.accountId {
            return PlexAccountManager.shared.getAccount(id: accountId)?.authToken ?? ""
        }
        return PlexAccountManager.shared.primaryAccount?.authToken ?? ""
    }
}
```

### Phase 6: Settings UI

#### 6.1 Account Management View

```swift
// New: Views/Settings/PlexAccountsView.swift

import SwiftUI

struct PlexAccountsView: View {
    @StateObject private var accountManager = PlexAccountManager.shared
    @State private var showAddAccount = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                Text("Plex Accounts")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.top, 60)

                if accountManager.accounts.isEmpty {
                    emptyState
                } else {
                    accountsList
                }

                addAccountButton
            }
            .padding(.bottom, 80)
        }
        .background(Color.black)
        .sheet(isPresented: $showAddAccount) {
            // Reuse existing Plex login flow
            PlexLoginSheet()
        }
    }

    private var accountsList: some View {
        SettingsSection(title: "Connected Accounts") {
            ForEach(accountManager.accounts) { account in
                AccountRow(account: account)
            }
        }
        .padding(.horizontal, 80)
    }

    private var addAccountButton: some View {
        SettingsSection(title: "Add Account") {
            SettingsActionRow(title: "Connect Another Plex Account") {
                showAddAccount = true
            }
        }
        .padding(.horizontal, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(.white.opacity(0.5))

            Text("No Accounts Connected")
                .font(.system(size: 32, weight: .semibold))

            Text("Connect a Plex account to browse your libraries.")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct AccountRow: View {
    let account: PlexAccount
    @StateObject private var accountManager = PlexAccountManager.shared

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 20) {
            // Account icon
            ZStack {
                Circle()
                    .fill(.orange.gradient)
                    .frame(width: 64, height: 64)

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Account info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(account.serverName)
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(.white)

                    if account.isPrimary {
                        Text("PRIMARY")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.orange.opacity(0.2))
                            )
                    }
                }

                Text(account.username)
                    .font(.system(size: 23))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // Menu indicator
            Image(systemName: "chevron.right")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isFocused ? .white.opacity(0.8) : .white.opacity(0.4))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isFocused ? .white.opacity(0.18) : .white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isFocused ? .white.opacity(0.25) : .white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
        .focusable()
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}
```

---

## Files Summary

### New Files
| File | Purpose |
|------|---------|
| `Services/Plex/PlexAccount.swift` | Account data model |
| `Services/Plex/PlexAccountManager.swift` | Multi-account storage & management |
| `Views/Settings/PlexAccountsView.swift` | Account management UI |

### Modified Files
| File | Changes |
|------|---------|
| `Models/Plex/PlexModels.swift` | Add `accountId`, `serverURL`, `uniqueId` to `PlexLibrary` |
| `Services/Plex/PlexAuthManager.swift` | Hand off to `PlexAccountManager` after auth |
| `Services/Plex/PlexDataStore.swift` | Store libraries per-account in `librariesByAccount` |
| `Services/Plex/LibrarySettingsManager.swift` | Use compound keys (`uniqueId`) |
| `Services/Cache/CacheManager.swift` | Namespace cache files by account ID |
| `Views/TVNavigation/TVSidebarView.swift` | Group libraries by account with section headers |
| `Views/Plex/PlexLibraryView.swift` | Use library's embedded account context |
| `Views/Plex/PlexDetailView.swift` | Pass account context for API calls |
| `Views/Settings/SettingsView.swift` | Add link to account management |

---

## Migration Strategy

### On First Launch After Update

```swift
// In RivuletApp.swift or AppDelegate
func application(_ application: UIApplication, didFinishLaunchingWithOptions...) {
    // Migrate legacy single-account credentials
    PlexAccountManager.shared.migrateFromLegacyAuth()

    // Migrate library settings keys
    if let primaryAccount = PlexAccountManager.shared.primaryAccount {
        LibrarySettingsManager.shared.migrateKeysForAccount(
            primaryAccount.id,
            libraryKeys: ["1", "2", "3", "4", "5"]  // Common library keys
        )
    }
}
```

### Cache File Migration

Option 1: **Lazy migration** - Old cache files remain, new ones use account-prefixed names. Old caches become orphaned over time.

Option 2: **Active migration** - Rename existing cache files to include account ID prefix on first launch.

---

## Testing Checklist

- [ ] Add first account - should become primary automatically
- [ ] Add second account - both appear in sidebar grouped by server name
- [ ] Remove an account - libraries disappear, cache cleaned up
- [ ] Set different primary - home screen hubs change
- [ ] Library visibility settings work independently per-account
- [ ] Navigate to library from Account A, then Account B - correct content loads
- [ ] Play media from different accounts - correct credentials used
- [ ] App restart - accounts persist correctly
- [ ] Migration from single-account version works

---

*Last updated: December 2024*
