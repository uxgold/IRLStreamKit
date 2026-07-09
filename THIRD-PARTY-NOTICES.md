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

Verified via the GitHub API at each pinned revision, 2026-07-10:

| Package | Wraps / is | Wrapper-repo license | Bundled-binary / effective license |
|---|---|---|---|
| `eerimoq/SrtSwift` | Haivision **SRT** (`libsrt`) | **none** (no LICENSE file) | libsrt is **MPL-2.0** — governs the bundled binary. |
| `eerimoq/DataChannel` | **libdatachannel** | **none** (no LICENSE file) | libdatachannel is **MPL-2.0**. |
| `eerimoq/Rist` | VideoLAN **librist** | **none** (no LICENSE file) | librist is **BSD-2-Clause**. |
| `eerimoq/MetalPetal` | **MetalPetal** | **MIT** (© Yu Ao) | MIT. |
| `apple/swift-collections` | — | **Apache-2.0** | Apache-2.0. |
| `Gisman4ik/TrueTime.swift` | **TrueTime.swift** | **Apache-2.0** | Apache-2.0. |

**Finding to resolve before shipping app binaries:** the three C-library
packaging forks — `SrtSwift`, `DataChannel`, `Rist` — carry **no license file** at
their pinned revisions. The prebuilt xcframeworks they bundle still carry their
upstream licenses (MPL-2.0 / MPL-2.0 / BSD-2-Clause — those obligations stand and
are covered below), but the *wrapper repos' own* content (the `Package.swift` and
any Swift glue) is technically unlicensed ("all rights reserved" by default).
Publishing IRLStreamKit's *source* is unaffected — it only references these
packages by URL, it does not redistribute them — but before distributing an app
binary built against them, close the gap one of these ways:

1. **Build the xcframeworks yourself** from the upstream C libraries
   ([Haivision/srt](https://github.com/Haivision/srt),
   [paullouisageneau/libdatachannel](https://github.com/paullouisageneau/libdatachannel),
   [librist](https://code.videolan.org/rist/librist)) so you control the packaging
   and its license; or
2. **Ask the fork maintainer to add a `LICENSE`** (Moblin depends on the same forks,
   so this benefits the wider ecosystem); or
3. rely on the bundled binaries' own licenses (MPL/BSD) and treat the trivial
   wrapper `Package.swift` as de-minimis — acceptable in practice, but (1) or (2)
   is cleaner for a shipped product.

**Resolution adopted (2026-07-10):** shipping proceeds under path 3, with path 2
pursued in parallel as a courtesy. Rationale:

- The code IRLStreamKit actually distributes in an app binary is the compiled
  **C libraries** (`libsrt`, `libdatachannel`, `librist`), whose licenses
  (MPL-2.0 / MPL-2.0 / BSD-2-Clause) are unambiguous and whose obligations are
  satisfied in *Obligations to satisfy on distribution* below.
- The only content in the `eerimoq/*` wrapper repos without an explicit license is
  a handful of lines of `Package.swift` build glue — no original library code.
  That glue is not redistributed inside the app binary (SwiftPM consumes it at
  build time only) and is de-minimis, so it creates no meaningful distribution
  risk for an App Store release.
- A courtesy request for the fork maintainer to add a permissive `LICENSE` has
  been (or is being) filed upstream; if accepted, this note should be updated to
  cite it and the de-minimis reliance can be dropped.

This closes the finding for release purposes. Re-audit if the forks add original
source beyond the build manifest, or if a future consumer redistributes the
wrapper repos themselves (as opposed to linking the binaries).

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
