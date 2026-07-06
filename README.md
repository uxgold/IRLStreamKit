# IRLStreamKit

An iOS live-streaming engine as a Swift package: camera/audio capture, hardware
H.264/HEVC encoding, RTMP, SRT with **SRTLA bonding** (cellular + WiFi bundling),
RIST, WHIP/WebRTC, adaptive bitrate (BELABOX/IRL algorithms), and RTMP/SRTLA/RIST
ingest servers.

The engine is extracted from [Moblin](https://github.com/eerimoq/moblin)
(MIT licensed) — see [UPSTREAM.md](UPSTREAM.md) for the vendoring policy, pinned
commit, and sync procedure, and [LICENSE](LICENSE) for attribution. All credit
for the engine internals belongs to Erik Moqvist and the Moblin contributors.

## Status

- Compiles standalone for iOS (deployment target 16.4, Xcode 26 SDK).
- `Vendor/` mirrors upstream byte-identically; `Shim/` holds the small set of
  app-layer types the engine references, extracted verbatim.
- No public API surface yet: everything is internal. The next step is a public
  facade (adapting upstream's `Media` class + `MediaDelegate` seam from
  `Moblin/Various/Media.swift`) — designed to live here, with app-specific
  adaptation in the consuming app.

## Build

```sh
xcodebuild -scheme IRLStreamKit -destination 'generic/platform=iOS' build
```

## Layout

```
Sources/IRLStreamKit/
  Vendor/    # byte-identical mirrors of upstream Moblin files — do not edit
  Shim/      # verbatim blocks extracted from app-entangled upstream files
scripts/
  sync-upstream.sh  # drift report / pull against upstream main
```
