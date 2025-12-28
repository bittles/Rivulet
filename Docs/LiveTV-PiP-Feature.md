# Live TV Picture-in-Picture Feature

## Overview

When a user exits the Live TV player to return to the guide or channel list, video streams should continue playing in a Picture-in-Picture overlay rather than stopping completely.

## Behavior

### Stream Lifecycle
- **Exit player → PiP**: Streams shrink to a PiP window in the corner, overlaying the guide/channel list
- **Tap PiP**: Returns to full-screen player with all active streams
- **Leave Live TV section**: PiP closes and all streams stop (e.g., navigating to Home, Library, Settings)
- **Select channel while PiP active**: Could replace focused stream or add to multiview (TBD)

### PiP Display
- Position: Bottom-right corner (or user preference)
- Size: ~25% of screen width for single stream
- Multi-stream: Show grid layout scaled down, or just the "focused" stream
- Semi-transparent border or shadow to distinguish from background content

## Architecture Changes

### Stream Ownership
Currently, `MultiStreamViewModel` owns streams and lives inside `LiveTVPlayerView`. This needs to change:

```
Current:
LiveTVContainerView
  └── GuideLayoutView / ChannelListView
  └── LiveTVPlayerView (fullScreenCover)
        └── MultiStreamViewModel (owns streams)

Proposed:
LiveTVContainerView
  └── LiveTVStreamManager (owns streams) ← NEW, shared state
  └── GuideLayoutView / ChannelListView
  └── LiveTVPlayerView (fullScreenCover, uses shared manager)
  └── LiveTVPiPOverlay (when player dismissed but streams active)
```

### New Components

1. **LiveTVStreamManager** (ObservableObject)
   - Owns all active stream slots
   - Manages MPV player instances
   - Provides `isActive`, `streamCount`, `focusedStream` etc.
   - Singleton or owned by LiveTVContainerView

2. **LiveTVPiPOverlay** (View)
   - Displays miniature stream(s) in corner
   - Focusable - pressing Select returns to full player
   - Shows channel name/number overlay
   - Animates in/out when appearing/dismissing

3. **Updated LiveTVPlayerView**
   - No longer owns streams, uses shared manager
   - Dismissing doesn't stop streams, just hides full-screen UI
   - "Exit" button explicitly stops streams AND dismisses

### Focus Management
- When PiP is visible, guide/channel list is still focusable
- PiP should be focusable via a single button/tap target
- Pressing Select on PiP → full-screen player
- Pressing Menu/Back on PiP → stop streams and remove PiP

## Implementation Phases

### Phase 1: Single-Stream PiP
1. Create `LiveTVStreamManager` to own stream state
2. Refactor `LiveTVPlayerView` to use shared manager
3. Create basic `LiveTVPiPOverlay` for single stream
4. Handle transitions: player dismiss → PiP, PiP tap → player

### Phase 2: Multi-Stream PiP
1. Extend PiP to show multiple streams (scaled grid or focused only)
2. Add stream indicator (e.g., "2/4 streams")
3. Handle adding streams from guide while PiP active

### Phase 3: Polish
1. PiP position preference (corner selection in settings)
2. Smooth animations for transitions
3. PiP size adjustment (pinch to resize?)
4. Audio handling (which stream has audio focus)

## Open Questions

- Should PiP be draggable/repositionable?
- When selecting a new channel from guide with PiP active:
  - Replace the focused stream?
  - Add as new stream (if under 4)?
  - Show a choice dialog?
- Should there be a "minimize to PiP" button in the player controls?
- Audio: If multiple streams, which one plays audio? Toggle-able?

## Settings

Consider adding:
- Enable/disable PiP behavior
- PiP corner position (top-left, top-right, bottom-left, bottom-right)
- PiP size (small, medium, large)
