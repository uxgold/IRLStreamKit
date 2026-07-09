# Third-party notices

IRLStreamKit is MIT-licensed (see [LICENSE](LICENSE)). It **vendors** one project
and **depends on** several others; their licenses and obligations are recorded here.
This is a good-faith audit — before a public release, confirm each item against the
dependency's own `LICENSE` at the pinned revision (see [Package.swift](Package.swift)
and [UPSTREAM.md](UPSTREAM.md)).

## Vendored (source copied into `Sources/IRLStreamKit/Vendor/`)

| Project | Upstream | License | Notes |
|---|---|---|---|
| Moblin media engine | [eerimoq/moblin](https://github.com/eerimoq/moblin) | MIT | Kept byte-identical; pinned commit + policy in [UPSTREAM.md](UPSTREAM.md). Credit to Erik Moqvist and the Moblin contributors. |

## SwiftPM dependencies (pinned by revision in `Package.swift`)

| Package | Wraps / is | Upstream license | Notes |
|---|---|---|---|
| `eerimoq/SrtSwift` | Haivision **SRT** (`libsrt`) | **MPL-2.0** | File-level copyleft — see obligation below. |
| `eerimoq/DataChannel` | **libdatachannel** | **MPL-2.0** | Same obligation. |
| `eerimoq/Rist` | VideoLAN **librist** | BSD-2-Clause | Permissive; retain the copyright notice. |
| `eerimoq/MetalPetal` | **MetalPetal** | MIT | Permissive. |
| `apple/swift-collections` | — | Apache-2.0 | Permissive; retain `NOTICE`/attribution if present. |
| `Gisman4ik/TrueTime.swift` | **TrueTime.swift** | MIT | Permissive. |

The `eerimoq/*` packages are build/packaging forks that bundle prebuilt
xcframeworks of the underlying C libraries; they are expected to retain the
upstream license of the code they wrap. **Confirm each fork's `LICENSE` at its
pinned revision** — a fork *could* relicense, and the bundled binary carries the
underlying library's license regardless of the wrapper.

## Obligations to satisfy on distribution

- **MPL-2.0 (SRT, libdatachannel).** The MPL is a *file-level* copyleft, not viral:
  you may ship binaries in an MIT product, but you must make the **source of the
  MPL-covered files available** (unmodified upstream source suffices, e.g. a link to
  [Haivision/srt](https://github.com/Haivision/srt) and
  [paullouisageneau/libdatachannel](https://github.com/paullouisageneau/libdatachannel)
  at the versions the forks bundle), and preserve their license headers. Since these
  ship as prebuilt binaries via the forks, record the exact upstream versions/commits
  the pinned forks build from.
- **BSD-2-Clause / MIT / Apache-2.0.** Retain the copyright and license text
  (this file plus each package's `LICENSE`). Apache-2.0: include any upstream
  `NOTICE` file if present.
- **AGPL (BELABOX srtla).** Used **only** as a black-box reference in the IRLTP
  testbed (cloned at container build time), **never** compiled into or distributed
  with IRLStreamKit — no obligation here. Noted for completeness.

## Not third-party

The IRLTP integration (`Sources/IRLStreamKit/Bonding/`, `Sources/IRLTPBonding/`)
and the facade (`Sources/IRLStreamKit/Facade/`) are original to this project (MIT).
`irltp-ffi` (linked as a binary) is MIT — see the [irltp](https://github.com/uxgold/irltp) repo.
