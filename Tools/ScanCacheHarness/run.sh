#!/bin/bash
# Builds and runs the scan-cache harness against the real app sources.
#
# The project has no test target, and ScanCacheStore is deliberately best-effort — no operation
# throws — so a bug there shows up as "the cache never works" rather than a crash. This is how
# that code gets checked. Run it after any change to ScanCacheStore, ScanCacheVersion, or
# FeatureDescriptor's encoding.
#
# Lives outside iClean/ on purpose: the Xcode project uses a file-system-synchronized group, so
# anything under iClean/ would be compiled into the app.
set -euo pipefail

cd "$(dirname "$0")"
SRC="../../iClean"
OUT="$(mktemp -d)/scan-cache-harness"

swiftc -O main.swift \
    "$SRC/ScanCache/ScanCacheStore.swift" \
    "$SRC/ScanCache/ScanCacheVersion.swift" \
    "$SRC/DetectionEngine/FeatureDescriptor.swift" \
    "$SRC/DetectionEngine/DetectionThresholds.swift" \
    -o "$OUT"

"$OUT"
