#!/usr/bin/env python3
"""Read existing Mimi diagnostics from a connected, trusted development iPhone."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='CoreDevice ID or device name; requires system trust/authorization')
    parser.add_argument('--output', type=Path, default=Path('ios/diagnostic-exports'))
    args = parser.parse_args()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    output = args.output / stamp
    output.mkdir(parents=True, exist_ok=False)
    results = []
    items = [('host', 'com.yuxino.osu', 'Documents/MimiDiagnostics'),
             ('snapshot', 'com.yuxino.osu', 'Documents/probe-status.json'),
             ('extension', 'com.yuxino.osu.MimiBroadcast', 'Documents/MimiDiagnostics')]
    for name, bundle, source in items:
        command = ['xcrun', 'devicectl', 'device', 'copy', 'from', '--device', args.device,
                   '--domain-type', 'appDataContainer', '--domain-identifier', bundle,
                   '--source', source, '--destination', str(output / name), '--timeout', '25',
                   '--json-output', str(output / f'{name}-transfer.json')]
        try:
            run = subprocess.run(command, capture_output=True, text=True, timeout=30)
            ok = run.returncode == 0
        except subprocess.TimeoutExpired:
            ok = False
        results.append({'item': name, 'copied': ok})
        print(f'{name}: {"copied" if ok else "unavailable (connection, permission, container or file)"}')
    (output / 'collection.json').write_text(json.dumps({
        'collectedAt': stamp, 'results': results,
        'note': 'Historical local records only. A copied running snapshot does not prove a live session. '
                'Extension-container access varies; absent extension logs are not proof no broadcast ran.'
    }, indent=2), encoding='utf-8')
    print(f'Saved to {output.resolve()}')
    return 0 if results[0]['copied'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
