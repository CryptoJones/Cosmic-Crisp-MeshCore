#!/usr/bin/env bash
# Run the SAME steps as .github/workflows/ci.yml, locally, before every push.
# If this script and the workflow ever disagree, the workflow is wrong or this
# is — fix them together. Exit non-zero on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== MeshCoreKit: swift test"
(cd Packages/MeshCoreKit && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests|failed" | tail -3)
(cd Packages/MeshCoreKit && swift test >/dev/null 2>&1)

echo "== xcodegen generate"
xcodegen generate >/dev/null

echo "== Pick an iPad simulator (same script as CI)"
xcodebuild -version
UDID=$(scripts/pick-ipad-simulator.sh)

echo "== Build & test (simulator)"
xcodebuild -project Cosmic-Crisp-MeshCore.xcodeproj -scheme CosmicCrisp \
  -destination "platform=iOS Simulator,id=$UDID" \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
  test 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED|BUILD FAILED" | tail -3
xcodebuild -project Cosmic-Crisp-MeshCore.xcodeproj -scheme CosmicCrisp \
  -destination "platform=iOS Simulator,id=$UDID" \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
  test >/dev/null 2>&1

echo "== Build (generic iOS device)"
xcodebuild -project Cosmic-Crisp-MeshCore.xcodeproj -scheme CosmicCrisp \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
xcodebuild -project Cosmic-Crisp-MeshCore.xcodeproj -scheme CosmicCrisp \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
  build >/dev/null 2>&1

echo "== ALL CI STEPS PASSED LOCALLY"
