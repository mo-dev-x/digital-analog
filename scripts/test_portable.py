#!/usr/bin/env python3
"""Run the portable Swift core tests and keep a machine-readable record of the outcome."""
import argparse
import datetime
import json
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--direct', action='store_true', help='Use scripts/test_core_direct.py instead of SwiftPM (Linux fallback)')
args = parser.parse_args()
out = ROOT / 'Verification' / 'local'
out.mkdir(parents=True, exist_ok=True)
results = []


def run(name, command):
    started = time.monotonic()
    with (out / (name + '.log')).open('w') as log:
        try:
            code = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT).returncode
        except OSError as error:
            log.write(str(error) + '\n')
            code = 127
    results.append({'name': name, 'status': 'passed' if code == 0 else 'failed', 'exit_code': code, 'seconds': round(time.monotonic() - started, 3), 'log': name + '.log'})
    print(name + ': ' + results[-1]['status'], flush=True)


if args.direct:
    run('swift-core', [sys.executable, 'scripts/test_core_direct.py'])
elif shutil.which('swift'):
    run('swift-core', ['swift', 'test', '--package-path', 'Core'])
else:
    results.append({'name': 'swift-core', 'status': 'unavailable', 'reason': 'Swift toolchain is not installed'})
    print('swift-core: unavailable', flush=True)

report = {'timestamp_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'platform': platform.platform(), 'python': platform.python_version(), 'scope': 'portable-core', 'ios_build': 'not run', 'device_tests': 'not run', 'results': results}
(out / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
print('Evidence: Verification/local/summary.json', flush=True)
raise SystemExit(1 if any(r['status'] != 'passed' for r in results) else 0)
