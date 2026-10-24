#!/bin/bash
# Unused-code scan. Builds through scripts/dev.sh (no Launch Services leftovers),
# then points Periphery at that build's index store instead of letting it run its
# own plain xcodebuild. Settings live in .periphery.yml; extra args pass through.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/dev.sh >/dev/null
DD="$HOME/Library/Developer/Xcode/DerivedData/LocalTranscriberDev-$(pwd -P | shasum | cut -c1-12).noindex"
periphery scan --skip-build --index-store-path "$DD/Index.noindex/DataStore" "$@"
