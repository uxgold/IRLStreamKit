# IRLStreamKit

An iOS live-streaming engine as a Swift package: camera/audio capture, hardware
H.264/HEVC encoding, RTMP, SRT with **SRTLA bonding** (cellular + WiFi bundling),
RIST, WHIP/WebRTC, adaptive bitrate (BELABOX/IRL algorithms), and RTMP/SRTLA/RIST
ingest servers.

The engine is extracted from [Moblin](https://github.com/eerimoq/moblin)
(MIT licensed) — see [UPSTREAM.md](UPSTREAM.md) for the vendoring policy, pinned
commit, and sync procedure, and [LICENSE](LICENSE) for attribution. All credit
for the engine internals belongs to Erik Moqvist and the Moblin contributors.

## Install

Add it with Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/uxgold/IRLStreamKit.git", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "IRLStreamKit", package: "IRLStreamKit"),
        // optional: .product(name: "IRLStreamKitTestSupport", package: "IRLStreamKit") in test targets
    ]),
]
```

Or in Xcode: **File → Add Package Dependencies…** → `https://github.com/uxgold/IRLStreamKit`.

The IRLTP bonding core ships as a checksummed binary `xcframework` (a GitHub
release asset), so a clean checkout builds with no sibling repo or Rust toolchain.
Requires iOS 17+ and the Xcode 26 SDK.

> **Versioning:** `0.x` — the public facade is stabilizing; minor bumps may make
> breaking API changes until `1.0`. Pin exactly (`.exact("0.1.0")`) if you need
> reproducibility across the app team.

## Status

- Compiles standalone for iOS (deployment target 17.0, Xcode 26 SDK); unit
  tests pass on the iOS simulator.
- `Vendor/` mirrors upstream byte-identically; `Shim/` holds the small set of
  app-layer types the engine references, extracted verbatim.
- Public facade in `Facade/`: a `StreamEngine` protocol (value-type state,
  events, typed errors — no vendor/UIKit types), the production
  `IRLStreamEngine`, and a SwiftUI `CameraPreviewView`. A second product,
  `IRLStreamKitTestSupport`, ships `FakeStreamEngine` for consumer TDD; fake
  and real engine share one package-internal state reducer so they cannot
  diverge.
- Containment rule: no vendored identifier may appear in a public/package
  declaration — upstream churn is absorbed by `Facade/MediaDelegateAdapter.swift`
  and `Facade/Mapping.swift` only. `scripts/check-containment.sh` enforces it.

## Usage sketch

```swift
import IRLStreamKit

let engine = IRLStreamEngine()          // hold one, app-lifetime
try await engine.startSession(camera: .back)   // preview
try await engine.goLive(StreamConfiguration(
    endpoint: .srtla(url: bondedIngestURL),
    video: VideoConfiguration(resolution: .fhd1080p, targetBitrate: 6_000_000)
))
// engine.state.phase / .stats / .bondingLinks drive the UI (@Observable);
// engine.events() feeds toasts/haptics/logging.
```

## Demo app

`Demo/` contains a field-test app (`IRLStreamKitDemo`) that consumes the
library strictly through its public API — no `@testable`, no internal access —
so it doubles as the reference integration. It exercises everything on a
phone: camera preview, go-live over SRTLA/SRT/RTMP, live bitrate changes, mic
mute, camera flip, bonding-link shares, audio meter, and a scrolling event log.

```sh
cd Demo && xcodegen generate
xcodebuild -project IRLStreamKitDemo.xcodeproj -scheme IRLStreamKitDemo \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

## Build & test

```sh
xcodebuild -scheme IRLStreamKit -destination 'generic/platform=iOS' build
xcodebuild test -scheme IRLStreamKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
scripts/check-containment.sh
```

## Layout

```
Sources/IRLStreamKit/
  Vendor/    # byte-identical mirrors of upstream Moblin files — do not edit
  Shim/      # verbatim blocks extracted from app-entangled upstream files
  Facade/    # the public API — the only surface consumers see
Sources/IRLStreamKitTestSupport/  # FakeStreamEngine for consumer TDD
Tests/IRLStreamKitTests/
scripts/
  sync-upstream.sh       # drift report / pull against upstream main
  check-containment.sh   # public surface must not leak vendored types
```

## License

IRLStreamKit is MIT-licensed ([LICENSE](LICENSE)). It vendors Moblin (MIT) and
depends on several third-party libraries (SRT and libdatachannel are MPL-2.0;
librist is BSD-2-Clause; the rest MIT/Apache-2.0). Their licenses and the
distribution obligations are recorded in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
