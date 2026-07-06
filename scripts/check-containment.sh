#!/bin/bash
# Containment gate: no vendored/shim identifier may appear in a public or
# package declaration of the facade. Keeps every Moblin sync's blast radius
# inside MediaDelegateAdapter.swift + Mapping.swift.
#
# Heuristic: checks declaration lines only (multi-line parameter lists are
# not fully covered); run after any facade change and during upstream syncs.

set -euo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
FORBIDDEN='Settings[A-Z]|MediaDelegate|BondingConnection|VideoUnitAttachParams|CaptureDevices?\b|SrtlaClient|RtmpStream|AdaptiveBitrateSettings|EngineSignal|[^a-zA-Z]Media[^a-zA-Z]|\bPreviewView\b|\bProcessor\b'

if grep -rnE '^[[:space:]]*(public|package)' \
        "$KIT/Sources/IRLStreamKit/Facade" \
        "$KIT/Sources/IRLStreamKitTestSupport" \
        --include='*.swift' | grep -E "$FORBIDDEN"; then
    echo "FAIL: vendored identifier leaked into a public/package declaration."
    exit 1
fi
echo "Containment OK: no vendored identifiers in the public surface."
