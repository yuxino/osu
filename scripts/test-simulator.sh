#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# First run: bundle exec ruby scripts/configure-simulator-harness.rb
# The named simulator must already be booted. No physical device is contacted.
mkdir -p .build
SIM_DEVICE=${1:?Usage: scripts/test-simulator.sh SIMULATOR_UDID}
xcodebuild -project ios/SimulatorHarness/MimiSimulator.xcodeproj -scheme MimiSimulator -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/simulator-harness build > .build/simulator-tests.log 2>&1
xcrun simctl install "$SIM_DEVICE" .build/simulator-harness/Build/Products/Release-iphonesimulator/MimiSimulator.app
xcrun simctl terminate "$SIM_DEVICE" com.yuxino.osu.SimulatorTests 2>/dev/null || true
SIM_DATA=$(xcrun simctl get_app_container "$SIM_DEVICE" com.yuxino.osu.SimulatorTests data)
# Preserve any earlier result, and require a newly created result for this run.
if [ -f "$SIM_DATA/Documents/simulator-test.json" ]; then
  mv "$SIM_DATA/Documents/simulator-test.json" "$SIM_DATA/Documents/simulator-test.previous.json"
fi
xcrun simctl launch "$SIM_DEVICE" com.yuxino.osu.SimulatorTests "${2:---verify-transport}"
python3 - "$SIM_DATA/Documents/simulator-test.json" <<'PY'
import json, pathlib, sys, time
path = pathlib.Path(sys.argv[1])
for _ in range(40):
    if path.exists():
        result = json.loads(path.read_text())
        print(json.dumps(result, indent=2))
        sys.exit(0 if result['passed'] else 1)
    time.sleep(0.5)
raise SystemExit('No fresh simulator result within 20 seconds')
PY
