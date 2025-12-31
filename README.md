# Rivulet

A native tvOS video streaming app designed for simplicity, combining **Plex** media server integration with **Live TV** support.

![tvOS 26+](https://img.shields.io/badge/tvOS-26+-000000?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift&logoColor=white)

## Features

### Plex Integration
- **PIN-based authentication** — Enter code at plex.tv/link from any device
- **Library browsing** — Movies, TV shows with poster grids and search
- **Continue Watching** — Resume playback from Plex hubs
- **Progress sync** — Watch progress reported back to your Plex server
- **HDR passthrough** — Full quality playback via MPV

### Live TV
- **Multiple sources** — Plex Live TV/DVR, Dispatcharr, or generic M3U playlists
- **Multi-stream** — Watch up to 4 channels simultaneously in grid layout
- **EPG support** — Program guide data from XMLTV sources
- **Unified interface** — All sources appear in a single channel list

### Design
- **Liquid Glass** — Native tvOS 26 design language
- **Slide-out sidebar** — Quick navigation without leaving content
- **Siri Remote optimized** — Intuitive scrubbing, focus management
- **Vertical scrolling** — Natural browsing experience

## Requirements

- Apple TV running tvOS 26 or later
- Xcode 26+ for building
- Plex Media Server (for Plex features)
- M3U/XMLTV source or Dispatcharr (for Live TV)

## Building

```bash
# Clone the repository
git clone https://github.com/yourusername/Rivulet.git
cd Rivulet

# Open in Xcode
open Rivulet.xcodeproj

# Build for Apple TV
xcodebuild -scheme Rivulet -destination 'generic/platform=tvOS' build
```

### Dependencies

Rivulet uses [MPV](https://mpv.io/) for video playback with Metal rendering. The MPV framework must be built for tvOS — see [mpv-build](https://github.com/AdrienMusic/mpv-build) for instructions.

## Architecture

```
Rivulet/
├── Models/           # Data models (Plex API, SwiftData)
├── Services/         # Business logic
│   ├── Plex/         # Authentication, networking, caching
│   ├── LiveTV/       # Provider protocol, data aggregation
│   ├── IPTV/         # M3U/XMLTV parsing
│   ├── Playback/     # MPV wrapper, progress reporting
│   └── Cache/        # File and image caching
├── Views/
│   ├── Plex/         # Library, detail, search views
│   ├── LiveTV/       # Channel list, multi-stream
│   ├── Player/       # Unified player, controls
│   └── Settings/     # Configuration UI
└── ContentView.swift # Main navigation
```

### Key Components

| Component | Purpose |
|-----------|---------|
| `PlexAuthManager` | PIN-based OAuth flow, token storage |
| `PlexNetworkManager` | Async API client with SSL handling |
| `LiveTVProvider` | Protocol for all Live TV sources |
| `LiveTVDataStore` | Aggregates channels from multiple providers |
| `MPVPlayerWrapper` | MPV adapter implementing `PlayerProtocol` |
| `UniversalPlayerView` | SwiftUI video player with scrubbing |

## Acknowledgments

- [MPV](https://mpv.io/) — Powerful open-source media player
- [Plex](https://plex.tv/) — Media server platform
- [Dispatcharr](https://github.com/Dispatcharr/Dispatcharr) — IPTV management

---

**Note**: Rivulet is not affiliated with or endorsed by Plex, Inc.
