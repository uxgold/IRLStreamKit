#!/bin/bash
# Diff the vendored tree against upstream Moblin and optionally pull updates.
#
# Usage:
#   scripts/sync-upstream.sh [path-to-moblin-checkout]   # report drift
#   APPLY=1 scripts/sync-upstream.sh [path]              # rsync upstream over Vendor/
#
# With no argument, clones upstream main into a temp directory.
# After APPLY, re-run the build and review `git diff` before committing;
# new upstream files may need new entries in Shim/.

set -euo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM_URL="https://github.com/eerimoq/moblin.git"

if [ $# -ge 1 ]; then
    MOBLIN="$1"
else
    MOBLIN="$(mktemp -d)/moblin"
    echo "Cloning upstream into $MOBLIN ..."
    git clone --depth 1 "$UPSTREAM_URL" "$MOBLIN"
fi

echo "Upstream commit: $(git -C "$MOBLIN" rev-parse HEAD)"
echo "Pinned commit:   $(grep -m1 'Pinned upstream commit' "$KIT/UPSTREAM.md" | awk '{print $NF}')"
echo

# vendored-path -> upstream-path (directories synced recursively)
MAPPINGS=(
    "Sources/IRLStreamKit/Vendor/Media:Moblin/Media"
    "Sources/IRLStreamKit/Vendor/Common/Various:Common/Various"
    "Sources/IRLStreamKit/Vendor/Various/Media.swift:Moblin/Various/Media.swift"
    "Sources/IRLStreamKit/Vendor/Various/Logger.swift:Moblin/Various/Logger.swift"
    "Sources/IRLStreamKit/Vendor/Various/SimpleTimer.swift:Moblin/Various/SimpleTimer.swift"
    "Sources/IRLStreamKit/Vendor/Various/Detection.swift:Moblin/Various/Detection.swift"
    "Sources/IRLStreamKit/Vendor/Various/Network/NetworkUtils.swift:Moblin/Various/Network/NetworkUtils.swift"
    "Sources/IRLStreamKit/Vendor/Various/Network/DnsLookup.swift:Moblin/Various/Network/DnsLookup.swift"
    "Sources/IRLStreamKit/Vendor/Various/Network/HttpServer.swift:Moblin/Various/Network/HttpServer.swift"
    "Sources/IRLStreamKit/Vendor/Various/Network/HttpClient.swift:Moblin/Various/Network/HttpClient.swift"
    "Sources/IRLStreamKit/Vendor/Various/Settings/SettingsIngests.swift:Moblin/Various/Settings/SettingsIngests.swift"
    "Sources/IRLStreamKit/Vendor/Various/Utils/CameraUtils.swift:Moblin/Various/Utils/CameraUtils.swift"
    "Sources/IRLStreamKit/Vendor/VideoEffects/EffectUtils.swift:Moblin/VideoEffects/EffectUtils.swift"
    "Sources/IRLStreamKit/Vendor/VideoEffects/VideoSourceEffect.swift:Moblin/VideoEffects/VideoSourceEffect.swift"
)

drift=0
for mapping in "${MAPPINGS[@]}"; do
    local_path="${mapping%%:*}"
    upstream_path="${mapping##*:}"
    if [ "${APPLY:-0}" = "1" ]; then
        if [ -d "$MOBLIN/$upstream_path" ]; then
            rsync -a --delete "$MOBLIN/$upstream_path/" "$KIT/$local_path/"
        else
            cp "$MOBLIN/$upstream_path" "$KIT/$local_path"
        fi
    else
        if ! diff -ru "$KIT/$local_path" "$MOBLIN/$upstream_path" > /dev/null 2>&1; then
            echo "DRIFT: $local_path <> $upstream_path"
            diff -ru "$KIT/$local_path" "$MOBLIN/$upstream_path" | head -40
            echo
            drift=1
        fi
    fi
done

if [ "${APPLY:-0}" = "1" ]; then
    echo "Applied upstream over Vendor/. Update the pinned commit in UPSTREAM.md,"
    echo "check Shim/ blocks against their origin files, rebuild, and review git diff."
elif [ "$drift" = "0" ]; then
    echo "Vendor/ matches upstream. Note: Shim/ blocks must be checked manually"
    echo "against their origin files listed in UPSTREAM.md."
fi
exit $drift
