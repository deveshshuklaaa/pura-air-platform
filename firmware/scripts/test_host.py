"""Compile and run the same portable C++ core used by ESP32; never opens serial ports."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--compiler', default=os.environ.get('CXX', 'g++'))
parser.add_argument('--emit', action='store_true', help='emit synthetic sensor-decoder payloads after tests')
args = parser.parse_args()
compiler = shutil.which(args.compiler)
if not compiler:
    raise SystemExit('Host C++ compiler required; set CXX or --compiler')
out = root / '.pio' / 'host-tests'
out.mkdir(parents=True, exist_ok=True)
exe = out / ('pura_tests.exe' if os.name == 'nt' else 'pura_tests')
subprocess.run([compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror',
                '-I' + str(root / 'lib/PuraCore/src'),
                str(root / 'lib/PuraCore/src/pura_core.cpp'),
                str(root / 'test/host_tests.cpp'), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
subprocess.run([sys.executable, str(root / 'scripts/test_config.py'), '--compiler', compiler], check=True)
if args.emit:
    fixture = subprocess.check_output([str(exe), '--emit'], text=True)
    dest = root / 'test/fixtures/telemetry.ndjson'
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(fixture, encoding='utf-8')
    print('Wrote synthetic decoder fixture: ' + str(dest))
