#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# First run: bundle exec ruby scripts/configure-simulator-harness.rb
# The named simulator must already be booted. No physical device is contacted.
mkdir -p .build
SIM_DEVICE=${1:?Usage: scripts/test-simulator.sh SIMULATOR_UDID}
SIM_TEST_MODE=${2:---verify-transport}
xcodebuild -project ios/SimulatorHarness/MimiSimulator.xcodeproj -scheme MimiSimulator -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/simulator-harness build > .build/simulator-tests.log 2>&1
xcrun simctl install "$SIM_DEVICE" .build/simulator-harness/Build/Products/Release-iphonesimulator/MimiSimulator.app
xcrun simctl terminate "$SIM_DEVICE" com.yuxino.osu.SimulatorTests 2>/dev/null || true
SIM_DATA=$(xcrun simctl get_app_container "$SIM_DEVICE" com.yuxino.osu.SimulatorTests data)
# Preserve any earlier result, and require a newly created result for this run.
if [ -f "$SIM_DATA/Documents/simulator-test.json" ]; then
  mv "$SIM_DATA/Documents/simulator-test.json" "$SIM_DATA/Documents/simulator-test.previous.json"
fi
if [ -f "$SIM_DATA/Documents/background-finish-ready.json" ]; then
  mv "$SIM_DATA/Documents/background-finish-ready.json" "$SIM_DATA/Documents/background-finish-ready.previous.json"
fi
xcrun simctl launch "$SIM_DEVICE" com.yuxino.osu.SimulatorTests "$SIM_TEST_MODE"
case "$SIM_TEST_MODE" in
  --verify-background-finish|--verify-background-timeout)
    python3 - "$SIM_DATA/Documents" <<'PY'
import pathlib, sys, time
directory = pathlib.Path(sys.argv[1])
for _ in range(40):
    if (directory / 'background-finish-ready.json').exists():
        sys.exit(0)
    result = directory / 'simulator-test.json'
    if result.exists():
        raise SystemExit(result.read_text())
    time.sleep(0.25)
raise SystemExit('Background fixture did not become ready')
PY
    xcrun simctl launch "$SIM_DEVICE" com.apple.Preferences
    ;;
esac
python3 - "$SIM_DATA/Documents/simulator-test.json" "${3:-20}" <<'PY'
import json, pathlib, sys, time
path = pathlib.Path(sys.argv[1])
timeout = int(sys.argv[2])
for _ in range(timeout * 2):
    if path.exists():
        result = json.loads(path.read_text())
        print(json.dumps(result, indent=2))
        sys.exit(0 if result['passed'] else 1)
    time.sleep(0.5)
raise SystemExit(f'No fresh simulator result within {timeout} seconds')
PY
