#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="$ROOT/Examples/simulator-app"
DERIVED_DATA_PATH="${NEPTUNE_DEMO_DERIVED_DATA:-$ROOT/.build/simulator-demo-derived-data}"
SIM_ID="${NEPTUNE_DEMO_SIMULATOR_ID:-}"

if ! command -v tuist >/dev/null 2>&1; then
  echo "tuist is required" >&2
  exit 1
fi

if [[ -z "$SIM_ID" ]]; then
  SIM_ID="$(xcrun simctl list devices | awk -F '[()]' '/Booted/{print $2; exit}')"
fi

if [[ -z "$SIM_ID" ]]; then
  echo "No booted iOS simulator found. Boot one first or set NEPTUNE_DEMO_SIMULATOR_ID." >&2
  exit 1
fi

cd "$DEMO_DIR"
tuist generate --no-open

xcodebuild \
  -project SimulatorApp.xcodeproj \
  -scheme SimulatorApp \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/SimulatorApp.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

xcrun simctl install "$SIM_ID" "$APP_PATH"
xcrun simctl launch "$SIM_ID" com.neptunekit.demo.ios

echo "Simulator demo launched: simulator_id=$SIM_ID app=$APP_PATH"
