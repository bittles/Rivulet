# Rivulet

A native tvOS video streaming app designed for simplicity, combining **Plex** media server integration with **Live TV** support.

This project has fairly opinionated designs and logic, with a few focal points:
- **Simplicity** - What is the best design to get me to the media I want to watch.
- **Apple-esque** - I like most of Apple's designs. I want this to feel *somewhat* native.
- **Vertical Scrolling** - I have never liked scrolling sideways. I use horizontal scrolling for some of the "infinite" lists, but use vertical scrolling whenever practical.
- **Live TV** - Plex's live TV is, to put it nicely, sub-par. I've spent too long trying to get it to work well for me (kudos if you don't have this problem). I don't want live TV in a separate app, so this solves my problems. You might could use this just for live tv. Go for it.
- **HomePod Integration** - The Plex app has never worked well when setting HomePod as the default audio output on my Apple TV. It hurts to have a HomePod sitting there collecting dust while my sub-par tv speakers play sound. This app helps the hurt.

![tvOS 26+](https://img.shields.io/badge/tvOS-26+-000000?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift&logoColor=white)

## Features

### Plex Integration
- PIN Authentication
- Pinned library selection
- Recently added, recently played
- Other lists pulled from Plex (if thats your thing)
- Hero banners (if thats your thing)

### Live TV Integration

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


## Acknowledgments

- [MPV](https://mpv.io/) — Powerful open-source media player
- [Plex](https://plex.tv/) — Media server platform
- [Dispatcharr](https://github.com/Dispatcharr/Dispatcharr) — IPTV management

---

**Note**: Rivulet is not affiliated with or endorsed by Plex, Inc.
