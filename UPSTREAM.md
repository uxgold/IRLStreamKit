# Upstream tracking

This package vendors the media engine of [Moblin](https://github.com/eerimoq/moblin)
(MIT licensed). Files under `Sources/IRLStreamKit/Vendor/` are kept **byte-identical**
to upstream so sync diffs stay trivial. Do not restyle or refactor them — adaptations
belong in the consuming app's adapter layer, and package-side glue belongs in
`Sources/IRLStreamKit/Shim/`.

Pinned upstream commit: 73dd0c9b538e2f41b9efdd6a679b2fbb40a5465c

## Vendored paths (verbatim mirrors)

| Local (under Sources/IRLStreamKit/Vendor/) | Upstream |
|---|---|
| `Media/` (entire tree) | `Moblin/Media/` |
| `Common/Various/` | `Common/Various/` |
| `Various/Logger.swift` | `Moblin/Various/Logger.swift` |
| `Various/SimpleTimer.swift` | `Moblin/Various/SimpleTimer.swift` |
| `Various/Detection.swift` | `Moblin/Various/Detection.swift` |
| `Various/Network/NetworkUtils.swift` | `Moblin/Various/Network/NetworkUtils.swift` |
| `Various/Network/DnsLookup.swift` | `Moblin/Various/Network/DnsLookup.swift` |
| `Various/Network/HttpServer.swift` | `Moblin/Various/Network/HttpServer.swift` |
| `Various/Network/HttpClient.swift` | `Moblin/Various/Network/HttpClient.swift` |
| `Various/Settings/SettingsIngests.swift` | `Moblin/Various/Settings/SettingsIngests.swift` |
| `Various/Utils/CameraUtils.swift` | `Moblin/Various/Utils/CameraUtils.swift` |
| `VideoEffects/EffectUtils.swift` | `Moblin/VideoEffects/EffectUtils.swift` |
| `VideoEffects/VideoSourceEffect.swift` | `Moblin/VideoEffects/VideoSourceEffect.swift` |

## Shims (verbatim blocks extracted from larger upstream files)

`Sources/IRLStreamKit/Shim/` contains type/function definitions copied verbatim
from upstream files that are too app-entangled to vendor whole. Each block is
annotated with its origin. When syncing, diff these blocks against their origin
files by hand:

- `AppLayerShims.swift` — from `Moblin/Various/Utils/Utils.swift`,
  `Moblin/Various/Utils/UiUtils.swift`, `Moblin/Various/Utils/FileSystemUtils.swift`,
  `Moblin/Various/Model/ModelCamera.swift`,
  `Moblin/Various/BondingStatisticsFormatter.swift`,
  `Moblin/VideoEffects/Dewarp360/Dewarp360Filter.swift`,
  `Moblin/View/Settings/WiFiAware/WiFiAwareSettingsView.swift`
- `SettingsShims.swift` — from `Moblin/Various/Settings/Settings.swift`,
  `Moblin/Various/Settings/SettingsStream.swift`,
  `Moblin/Various/Settings/SettingsScene.swift`

## Sync procedure

1. `scripts/sync-upstream.sh` — reports drift between `Vendor/` and upstream main.
2. `APPLY=1 scripts/sync-upstream.sh` — pulls upstream over `Vendor/`.
3. Diff the shim origin files for changes to the extracted blocks.
4. Update the pinned commit above; check `Package.swift` revisions against
   Moblin's `Package.resolved` (upstream tracks its own forks' main branches).
5. Build: `xcodebuild -scheme IRLStreamKit -destination 'generic/platform=iOS' build`.
   New upstream symbols may need new shim entries.

## Dependency pins

The eerimoq fork packages (SrtSwift, DataChannel, Rist, MetalPetal) are pinned by
revision to what Moblin resolved at the pinned commit. These are personal forks —
consider mirroring them if this package becomes load-bearing.
