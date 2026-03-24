#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if command -v xcrun >/dev/null 2>&1; then
  SWIFT_BIN="$(xcrun --find swift)"
else
  SWIFT_BIN="$(command -v swift)"
fi

"${SWIFT_BIN}" run NeptuneSDKiOSSmokeDemo "$@"
