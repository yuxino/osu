#!/usr/bin/env python3
"""Probe the island lookup in two simulator processes; never contacts a phone.

Requires configure-simulator-harness.rb and a built MimiSimulator scheme.
Exit 1 means the independent-process subtitle acceptance failed, even if the
failure was reproduced successfully. This is not a ReplayKit extension test.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True).stdout.strip()


def wait_json(path, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return json.loads(path.read_text())
        time.sleep(0.2)
    raise RuntimeError(f'No fresh result: {path}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('simulator')
    args = parser.parse_args()
    device = args.simulator
    root = Path(__file__).resolve().parent.parent
    products = root / '.build/simulator-harness/Build/Products/Release-iphonesimulator'
    host_id = 'com.yuxino.osu.SimulatorTests'
    probe_id = host_id + '.ProcessProbe'
    containers = []
    for bundle, product in [(host_id, 'MimiSimulator'), (probe_id, 'IslandProcessProbe')]:
        run('xcrun', 'simctl', 'terminate', device, bundle, check=False)
        run('xcrun', 'simctl', 'install', device, str(products / (product + '.app')))
        containers.append(Path(run('xcrun', 'simctl', 'get_app_container', device, bundle, 'data')) / 'Documents')
    ready_path = containers[0] / 'island-probe-ready.json'
    result_path = containers[1] / 'island-process-result.json'
    for path in [ready_path, result_path]:
        if path.exists():
            path.replace(path.with_suffix('.previous.json'))
    run('xcrun', 'simctl', 'launch', '--terminate-running-process', device, host_id, '--island-process-host')
    ready = wait_json(ready_path)
    try:
        run('xcrun', 'simctl', 'launch', '--terminate-running-process', device, probe_id, '--activity-id', ready['activityID'])
        result = wait_json(result_path)
        result['hostPID'] = ready['hostPID']
        result['differentProcesses'] = result['probePID'] != ready['hostPID']
        result['acceptancePassed'] = bool(result['acceptancePassed'] and result['differentProcesses'])
        result['replayKitVerified'] = False
        output = root / '.build/island-process-result.json'
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
        print(output.read_text())
        return 0 if result['acceptancePassed'] else 1
    finally:
        # Let the host's 20-second task end its own Live Activity, rather than
        # force-killing it and leaving an orphaned test activity on the simulator.
        run('xcrun', 'simctl', 'terminate', device, probe_id, check=False)


if __name__ == '__main__':
    raise SystemExit(main())
