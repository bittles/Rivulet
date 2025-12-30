# MPV Options Reference for Rivulet

This document covers MPVKit/libmpv options, properties, and commands available for use in Rivulet on tvOS.

## Overview

Rivulet uses [MPVKit](https://github.com/mpvkit/MPVKit) which provides libmpv for iOS/tvOS/macOS. MPVKit bundles mpv with FFmpeg and MoltenVK (Vulkan-to-Metal translation).

**Important Limitation**: MPVKit's Metal support is experimental. The gpu-next renderer uses libplacebo which requires Vulkan, so on Apple platforms it goes through MoltenVK regardless of `gpu-api` setting.

---

## Video Output Options

### `--vo` (Video Output Driver)
| Value | Description | tvOS Support |
|-------|-------------|--------------|
| `gpu-next` | Modern renderer using libplacebo (recommended for HDR) | ✅ Via MoltenVK |
| `gpu` | Legacy GPU renderer | ✅ Via MoltenVK |
| `null` | No video output | ✅ |

**Note**: `gpu-next` is now the default in mpv 0.41+. It provides better HDR handling and color management.

### `--gpu-api` (Graphics API)
| Value | Description | tvOS Support |
|-------|-------------|--------------|
| `vulkan` | Vulkan API (via MoltenVK on Apple) | ✅ Required for gpu-next |
| `opengl` | OpenGL/OpenGL ES | ⚠️ Limited |
| `metal` | Native Metal | ❌ Not supported by gpu-next |

**Note**: Despite setting `metal`, gpu-next always uses Vulkan via MoltenVK on Apple platforms.

### `--hwdec` (Hardware Decoding)
| Value | Description | tvOS Support |
|-------|-------------|--------------|
| `videotoolbox` | Apple VideoToolbox (zero-copy) | ✅ Recommended |
| `videotoolbox-copy` | VideoToolbox with copy | ✅ |
| `auto` | Auto-select best available | ✅ |
| `no` | Software decoding only | ✅ |

### `--hwdec-codecs`
Comma-separated list of codecs to hardware decode. Default: `h264,vc1,hevc,vp8,vp9,av1`

Use `all` to attempt hardware decoding for all codecs.

### `--gpu-hwdec-interop`
| Value | Description |
|-------|-------------|
| `auto` | Auto-detect (default) |
| `videotoolbox` | Force VideoToolbox interop |
| `all` | Load all available interops |

### `--target-colorspace-hint`
Enable HDR passthrough. When `yes`, mpv hints the display about the video's colorspace.

```swift
// HDR passthrough setup
checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))
```

---

## Scaling & Quality Options

### Upscaling (`--scale`)
| Value | Quality | Performance |
|-------|---------|-------------|
| `bilinear` | Low | Fast |
| `bicubic_fast` | Medium | Fast |
| `spline36` | High | Medium |
| `spline64` | Higher | Slower |
| `ewa_lanczos` | Best | GPU intensive |
| `ewa_lanczossharp` | Best (sharpened) | GPU intensive |

### Downscaling (`--dscale`)
| Value | Description |
|-------|-------------|
| `mitchell` | Best for downscaling (recommended) |
| `bilinear` | Fast, lower quality |
| `hermite` | Good balance |

### Chroma Upscaling (`--cscale`)
Same options as `--scale`. Human eyes are less sensitive to chroma, so lower quality is acceptable.

### Other Quality Options
| Option | Values | Description |
|--------|--------|-------------|
| `--deband` | `yes`/`no` | Remove banding artifacts |
| `--deband-iterations` | 1-16 | Deband passes (higher = better but slower) |
| `--deband-threshold` | 0-4096 | Deband strength |
| `--interpolation` | `yes`/`no` | Frame interpolation for smoother motion |
| `--video-sync` | `audio`/`display-resample` | Sync method |
| `--correct-downscaling` | `yes`/`no` | Higher quality downscaling |
| `--linear-downscaling` | `yes`/`no` | Downscale in linear light |
| `--dither` | `yes`/`no` | Dithering for color depth |

---

## Audio Options

### `--ao` (Audio Output Driver)
| Value | Platform | Description |
|-------|----------|-------------|
| `audiounit` | iOS/tvOS | Native AudioUnit driver |
| `coreaudio` | macOS | CoreAudio driver |
| `null` | All | No audio output |

### `--audio-channels`
| Value | Description |
|-------|-------------|
| `stereo` | 2.0 stereo |
| `5.1` | 5.1 surround |
| `7.1` | 7.1 surround |
| `auto` | Match source (can cause issues) |
| `auto-safe` | Auto but reject problematic layouts (default) |

**Warning**: `auto` can expose invalid channel layouts over HDMI/AirPlay.

**tvOS 7.1 Bug**: tvOS reports 8-channel capability over HDMI but returns `kAudioChannelLabel_Unknown` for channels 7-8 instead of Side Left/Right. Stock MPVKit crashes with `sp255` (unknown speaker). **Requires patched MPVKit** to map unknown labels to correct 7.1 positions. See `ao_audiounit.m` patch in the plan file.

### `--audio-format`
| Value | Description |
|-------|-------------|
| `s16` | 16-bit signed integer |
| `s32` | 32-bit signed integer |
| `float` | 32-bit float |
| `floatp` | 32-bit float planar |

### `--audio-spdif` (Passthrough)
Comma-separated list of codecs to pass through:
- `ac3` - Dolby Digital
- `eac3` - Dolby Digital Plus
- `dts` - DTS (core only)
- `dts-hd` - DTS-HD Master Audio
- `truehd` - Dolby TrueHD

```swift
// HDMI receiver passthrough
checkError(mpv_set_option_string(mpv, "audio-spdif", "ac3,eac3,dts-hd,truehd"))
```

**Note**: Passthrough bypasses channel limits and goes directly to the receiver.

### `--af` (Audio Filters)
```swift
// Force downmix to 5.1 or stereo
checkError(mpv_set_option_string(mpv, "af", "lavfi=[aformat=channel_layouts=5.1|stereo]"))
```

### Other Audio Options
| Option | Description |
|--------|-------------|
| `--volume` | Initial volume (0-100) |
| `--mute` | Start muted |
| `--audio-exclusive` | Exclusive audio device access |
| `--audio-buffer` | Audio buffer size in seconds |
| `--ad-lavc-downmix` | Request decoder downmix |

---

## Subtitle Options

| Option | Values | Description |
|--------|--------|-------------|
| `--sub-auto` | `no`/`exact`/`fuzzy`/`all` | External subtitle loading |
| `--slang` | `en,eng,ja` | Preferred subtitle languages |
| `--sid` | track ID or `no` | Select subtitle track |
| `--secondary-sid` | track ID | Second subtitle track |
| `--sub-visibility` | `yes`/`no` | Show/hide subtitles |
| `--sub-delay` | seconds | Subtitle timing offset |
| `--sub-scale` | float | Subtitle size multiplier |

---

## Cache & Network Options

### Cache Settings
| Option | Description | Default |
|--------|-------------|---------|
| `--cache` | Enable caching | `yes` |
| `--cache-secs` | Target cache duration | 10 |
| `--demuxer-max-bytes` | Forward buffer size | 150MiB |
| `--demuxer-max-back-bytes` | Backward buffer size | 50MiB |
| `--demuxer-readahead-secs` | Readahead duration | 20 |

### Network Settings
| Option | Description |
|--------|-------------|
| `--demuxer-lavf-o` | FFmpeg demuxer options |
| `--http-header-fields` | Custom HTTP headers |
| `--user-agent` | HTTP user agent |
| `--referrer` | HTTP referrer |

```swift
// Enable network reconnection
checkError(mpv_set_option_string(mpv, "demuxer-lavf-o", "reconnect=1,reconnect_streamed=1"))
```

---

## Properties (Runtime Read/Write)

Properties can be read with `mpv_get_property()` and written with `mpv_set_property()`.

### Playback State
| Property | Type | Description |
|----------|------|-------------|
| `pause` | Flag | Paused state |
| `paused-for-cache` | Flag | Buffering |
| `core-idle` | Flag | Player is idle |
| `eof-reached` | Flag | End of file reached |
| `seeking` | Flag | Currently seeking |
| `idle-active` | Flag | Player idle (no file) |

### Time & Position
| Property | Type | Description |
|----------|------|-------------|
| `time-pos` | Double | Current position (seconds) |
| `duration` | Double | Total duration |
| `percent-pos` | Double | Position as percentage |
| `playback-time` | Double | Playback position (alias) |
| `time-remaining` | Double | Time until end |

### Tracks
| Property | Type | Description |
|----------|------|-------------|
| `track-list` | Node | List of all tracks |
| `track-list/count` | Int64 | Number of tracks |
| `aid` | Int64/String | Current audio track |
| `sid` | Int64/String | Current subtitle track |
| `vid` | Int64/String | Current video track |

Per-track properties (replace N with index):
- `track-list/N/id` - Track ID
- `track-list/N/type` - "video", "audio", "sub"
- `track-list/N/lang` - Language code
- `track-list/N/title` - Track title
- `track-list/N/codec` - Codec name
- `track-list/N/default` - Is default track
- `track-list/N/forced` - Is forced track
- `track-list/N/selected` - Is currently selected

### Video Info
| Property | Type | Description |
|----------|------|-------------|
| `video-params/w` | Int64 | Video width |
| `video-params/h` | Int64 | Video height |
| `video-params/primaries` | String | Color primaries |
| `video-params/gamma` | String | Gamma/transfer function |
| `video-params/sig-peak` | Double | HDR peak luminance |
| `video-params/colormatrix` | String | Color matrix |

### Audio/Volume
| Property | Type | Description |
|----------|------|-------------|
| `volume` | Double | Volume level (0-100) |
| `mute` | Flag | Muted state |
| `speed` | Double | Playback speed |

---

## Commands

Commands are executed with `mpv_command()` or `mpv_command_string()`.

### Playback Control
| Command | Arguments | Description |
|---------|-----------|-------------|
| `loadfile` | url [flags] | Load a file |
| `stop` | - | Stop playback |
| `quit` | [code] | Quit player |
| `seek` | seconds [mode] | Seek position |
| `frame-step` | - | Step one frame forward |
| `frame-back-step` | - | Step one frame backward |

Seek modes:
- `relative` (default) - Relative to current position
- `absolute` - Absolute position
- `absolute-percent` - Percentage of duration

### Property Commands
| Command | Arguments | Description |
|---------|-----------|-------------|
| `set` | property value | Set property value |
| `add` | property [value] | Add to property |
| `cycle` | property [up/down] | Cycle property values |
| `multiply` | property value | Multiply property |

### Track Commands
| Command | Arguments | Description |
|---------|-----------|-------------|
| `audio-add` | url [flags] | Add external audio |
| `sub-add` | url [flags] | Add external subtitles |
| `audio-remove` | [id] | Remove audio track |
| `sub-remove` | [id] | Remove subtitle track |

---

## Options That DON'T Work on tvOS

| Option | Reason |
|--------|--------|
| `--gpu-api=metal` | gpu-next requires Vulkan (uses MoltenVK) |
| `--opengl-pbo` | OpenGL-specific, not for Vulkan/Metal |
| `--vulkan-async-compute` | May not be supported by MoltenVK |
| `--vulkan-async-transfer` | May not be supported by MoltenVK |
| `--ytdl` | youtube-dl not available on tvOS |
| `--input-*` | Keyboard/mouse input options irrelevant |
| `--screen` | Display selection not applicable |
| `--fullscreen` | Managed by tvOS |

---

## Recommended Configuration

### VOD Playback (Movies/TV Shows)
```swift
// Video output
mpv_set_option_string(mpv, "vo", "gpu-next")
mpv_set_option_string(mpv, "gpu-api", "vulkan")
mpv_set_option_string(mpv, "hwdec", "videotoolbox")
mpv_set_option_string(mpv, "target-colorspace-hint", "yes")
mpv_set_option_string(mpv, "gpu-hwdec-interop", "videotoolbox")

// Cache for smooth 4K playback
mpv_set_option_string(mpv, "cache", "yes")
mpv_set_option_string(mpv, "demuxer-max-bytes", "250MiB")
mpv_set_option_string(mpv, "demuxer-max-back-bytes", "100MiB")
mpv_set_option_string(mpv, "cache-secs", "30")

// Audio (7.1 requires patched MPVKit - see tvOS 7.1 Bug note above)
mpv_set_option_string(mpv, "audio-channels", "7.1,5.1,stereo")
```

### Live TV (Low Latency)
```swift
// Minimal buffering
mpv_set_option_string(mpv, "cache", "yes")
mpv_set_option_string(mpv, "demuxer-max-bytes", "32MiB")
mpv_set_option_string(mpv, "demuxer-max-back-bytes", "0")
mpv_set_option_string(mpv, "cache-secs", "10")

// Fast scaling (reduce CPU/GPU load)
mpv_set_option_string(mpv, "scale", "bilinear")
mpv_set_option_string(mpv, "dscale", "bilinear")
mpv_set_option_string(mpv, "deband", "no")
mpv_set_option_string(mpv, "interpolation", "no")
```

---

## API Functions

### Before `mpv_initialize()`
Use `mpv_set_option_string()` or `mpv_set_option()`:
```swift
mpv_set_option_string(mpv, "vo", "gpu-next")
```

### After `mpv_initialize()`
Use `mpv_set_property_string()` or `mpv_set_property()`:
```swift
mpv_set_property_string(mpv, "pause", "yes")
```

### Observing Properties
```swift
mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
```

### Executing Commands
```swift
// Array-based command
let args = ["loadfile", url, "replace"]
mpv_command(mpv, args)

// Single command
mpv_command_string(mpv, "seek 10 relative")
```

---

## References

- [mpv Manual (Stable)](https://mpv.io/manual/stable/)
- [mpv GitHub - options.rst](https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst)
- [mpv GitHub - input.rst](https://github.com/mpv-player/mpv/blob/master/DOCS/man/input.rst)
- [MPVKit GitHub](https://github.com/mpvkit/MPVKit)
- [GPU Next vs GPU Wiki](https://github.com/mpv-player/mpv/wiki/GPU-Next-vs-GPU)
- [libmpv client.h Doxygen](https://www.ccoderun.ca/programming/doxygen/mpv/client_8h.html)
