#!/usr/bin/env bash
# Print the UDID of an iPad simulator that xcodebuild will actually accept for
# this scheme (i.e. one whose runtime is installed for the selected Xcode).
# Asking simctl alone is not enough: a runner can list a device whose iOS
# platform is missing from the selected Xcode, and xcodebuild then rejects it.
set -euo pipefail
cd "$(dirname "$0")/.."
LINE=$(xcodebuild -project Cosmic-Crisp-MeshCore.xcodeproj -scheme CosmicCrisp -showdestinations 2>/dev/null \
  | grep "platform:iOS Simulator" | grep "name:iPad" | grep -v "error:" | sort | tail -1)
UDID=$(sed -n 's/.*id:\([0-9A-F-]*\).*/\1/p' <<<"$LINE")
if [ -z "$UDID" ]; then echo "no usable iPad simulator destination" >&2; exit 1; fi
echo "picked: $LINE" >&2
echo "$UDID"
