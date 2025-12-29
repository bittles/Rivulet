# Rivulet - Claude Context

Rivulet is a tvOS media client for Plex and IPTV. It uses SwiftUI with MPV for video playback with HDR passthrough.

## Quick Reference

- **Platform**: tvOS 26+ (Apple TV)
- **Language**: Swift 6
- **UI Framework**: SwiftUI
- **Video Player**: MPV via libmpv (Metal rendering, HDR passthrough)
- **Design Guide**: See `Docs/DESIGN_GUIDE.md` for UI/UX patterns

## Project Structure

```
Rivulet/
├── Models/
│   ├── Plex/           # Plex API models (PlexMetadata, PlexStream, etc.)
│   └── SwiftData/      # Persistent models (Channel, EPGProgram, PlexServer)
├── Services/
│   ├── Plex/           # PlexNetworkManager, PlexAuthManager, PlexDataStore
│   ├── Playback/       # MPVPlayerWrapper, AVPlayerWrapper, MediaTrack
│   ├── LiveTV/         # PlexLiveTVProvider, IPTVProvider, LiveTVDataStore
│   ├── IPTV/           # M3UParser, XMLTVParser, DispatcharrService
│   ├── Cache/          # CacheManager, ImageCacheManager
│   └── Focus/          # FocusScopeManager (tvOS focus isolation)
├── Views/
│   ├── Player/         # UniversalPlayerView, PlayerControlsOverlay
│   │   ├── MPV/        # MPVPlayerView, MPVMetalViewController
│   │   └── PostVideo/  # Post-playback summary overlays
│   ├── Plex/           # PlexHomeView, PlexLibraryView, PlexDetailView
│   ├── LiveTV/         # ChannelListView, GuideLayoutView, LiveTVPlayerView
│   ├── Settings/       # SettingsView, SettingsComponents
│   ├── Components/     # CachedAsyncImage, GlassRowStyle
│   ├── TVNavigation/   # TVSidebarView, NavigationEnvironment
│   └── Root/           # SidebarView
└── Docs/
    └── DESIGN_GUIDE.md # Comprehensive UI/UX documentation
```

## Key Architectural Patterns

### Focus Management (tvOS)

Uses `FocusScopeManager` for scope-based focus isolation. Critical for overlays and modals.

**Scopes**: `.content`, `.sidebar`, `.player`, `.playerInfoBar`, `.postVideo`, `.modal`, `.settings`, `.detail`, `.channelPicker`, `.guide`

```swift
// Activate a scope (saves current focus, pushes to stack)
focusScopeManager.activate(.postVideo)

// Deactivate (pops stack, restores previous focus)
focusScopeManager.deactivate()

// Check if scope is active
focusScopeManager.isScopeActive(.postVideo)
```

**Important**: `fullScreenCover` does NOT inherit environment values. Views presented this way must create their own `FocusScopeManager` instance:

```swift
struct UniversalPlayerView: View {
    @StateObject private var focusScopeManager = FocusScopeManager()

    var body: some View {
        // ... content ...
        .environment(\.focusScopeManager, focusScopeManager)
    }
}
```

### Video Player Architecture

- **UniversalPlayerView**: Main SwiftUI player container
- **UniversalPlayerViewModel**: Manages playback state, markers, post-video logic
- **MPVPlayerWrapper**: Bridges MPV to Swift (Combine publishers for state)
- **MPVMetalViewController**: UIViewController hosting Metal layer for MPV rendering

**Playback States**: `.idle`, `.loading`, `.playing`, `.paused`, `.buffering`, `.ended`, `.failed`

### Plex Metadata Hierarchy

For TV shows:
- **Show** (`grandparentRatingKey`) → **Season** (`parentRatingKey`) → **Episode** (`ratingKey`)
- Episode has `index` (episode number) and `parentIndex` (season number)

**Note**: Items from "Continue Watching" hub may lack parent metadata. Use `PlexNetworkManager.getMetadata()` to fetch full details.

### Glass UI Style

All focusable rows use consistent styling (see `Docs/DESIGN_GUIDE.md`):

```swift
// Background
.fill(isFocused ? .white.opacity(0.18) : .white.opacity(0.08))
.strokeBorder(isFocused ? .white.opacity(0.25) : .white.opacity(0.08), lineWidth: 1)

// Scale
.scaleEffect(isFocused ? 1.02 : 1.0)

// Animation
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
```

## Common Tasks

### Adding a New Focus Scope

1. Add to `FocusScopeManager.swift`:
   ```swift
   static let myScope = FocusScope("myScope")
   ```

2. Activate when overlay/view appears:
   ```swift
   .onChange(of: showMyOverlay) { _, show in
       if show { focusScopeManager.activate(.myScope) }
       else { focusScopeManager.deactivate() }
   }
   ```

3. Make buttons focusable only when scope is active:
   ```swift
   .focusable(focusScopeManager.isScopeActive(.myScope))
   ```

### Fetching Next Episode

```swift
// Get episodes in current season
let episodes = try await networkManager.getChildren(
    serverURL: serverURL,
    authToken: authToken,
    ratingKey: metadata.parentRatingKey  // Season key
)

// Find next episode
let next = episodes.first(where: { $0.index == currentEpisodeIndex + 1 })
```

### Adding Settings

Use components from `SettingsComponents.swift`:
- `SettingsRow` - Navigation with chevron
- `SettingsToggleRow` - On/Off toggle
- `SettingsPickerRow` - Cycles through options
- `SettingsActionRow` - Action button (supports destructive)

### Image Loading

Always use `CachedAsyncImage` for remote images:
```swift
CachedAsyncImage(url: imageURL) { phase in
    switch phase {
    case .success(let image): image.resizable()
    case .empty: ProgressView()
    case .failure: Image(systemName: "photo")
    }
}
```

## Build & Run

```bash
# Build for tvOS Simulator
xcodebuild -scheme Rivulet -destination 'platform=tvOS Simulator,name=Apple TV' build

# Build for device
xcodebuild -scheme Rivulet -destination 'platform=tvOS,name=My Apple TV' build
```

## Key Files

| Purpose | File |
|---------|------|
| Main player | `Views/Player/UniversalPlayerView.swift` |
| Player state | `Views/Player/UniversalPlayerViewModel.swift` |
| MPV integration | `Services/Playback/MPVPlayerWrapper.swift` |
| Focus management | `Services/Focus/FocusScopeManager.swift` |
| Plex API | `Services/Plex/PlexNetworkManager.swift` |
| Glass row styling | `Views/Components/GlassRowStyle.swift` |
| Settings components | `Views/Settings/SettingsComponents.swift` |
| Design patterns | `Docs/DESIGN_GUIDE.md` |

## Design Philosophy

From `Docs/DESIGN_GUIDE.md`:

- **Simplicity First**: Remove rather than add. The interface should feel calm.
- **Elegant Restraint**: Subtle effects (2% scale, soft glow) over flashy ones.
- **Liquid Glass**: Translucent backgrounds with subtle borders (tvOS 26 aesthetic).
- **Subtle Motion**: Small scale effects, natural animations.
- **Invisible Complexity**: Complex features should feel simple to use.

**Design Don'ts**:
- No over-decoration (gradients, unnecessary shadows)
- No aggressive animations (bouncing, overshooting)
- No redundant icons/labels
- No "just in case" features

## Troubleshooting

### Focus Not Working in Overlay
- Check if overlay is in a `fullScreenCover` (environment not inherited)
- Ensure `focusScopeManager.activate(.scope)` is called when overlay appears
- Use `@ObservedObject` for focus manager, not `@Environment`
- Pass `isActive` state to child components as a parameter

### Video Not Shrinking/Positioning
- Check `VideoFrameState` offset values (positive = padding from top-left with `.topLeading` anchor)
- Ensure `videoFrameState` is being set to `.shrunk`

### Post-Video Not Triggering
- Check if `hasTriggeredPostVideo` flag needs resetting
- Verify credits marker detection in `checkMarkers(at:)`
- Ensure `duration > 60` for time-based trigger (45s before end)
