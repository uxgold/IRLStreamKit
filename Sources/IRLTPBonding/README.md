# IRLTPBonding

Swift surface for the IRLTP sans-IO SRTLA sender (the Rust core from the sibling
`irltp` repo), exposed via UniFFI.

## Layout

- `IRLTPBondingSmoke.swift` — hand-written; a minimal in-process exercise of the
  core (proves it links and runs on iOS).
- `irltp_ffi.swift` — **generated** (gitignored). The UniFFI Swift API.
- `../../Frameworks/irltp_ffi.xcframework` — **generated** (gitignored, ~40 MB).
  The compiled Rust static libs (ios-arm64 + ios-arm64-simulator) + C module.

## Regenerating the artifacts

The two generated pieces are build artifacts, not checked in. After a fresh
clone (or when the Rust core changes), build and install them:

```sh
cd ../irltp            # the sibling irltp repo
./scripts/build-ios.sh ~/IRLStreamKit    # builds + installs both artifacts here
```

The `IRLTPBonding` SPM target won't compile until this runs. (A future release
can host the xcframework as a remote `binaryTarget` with url+checksum, like the
`eerimoq` deps, to make a fresh checkout self-building.)

## Architecture

The core is sans-IO: Swift owns the transport (one interface-pinned
`NWConnection` per bonded link) and the clock; it feeds datagrams + a monotonic
millisecond timestamp into `IrltpSender` and executes the returned
`[IrltpAction]` (`send` on a link, `forwardToLocalSrt`, `reconnect`). This keeps
iOS interface binding in Network.framework and the SRTLA protocol in Rust.
