#!/usr/bin/env python3
"""Record inputs and environment. Uses only Python's standard library."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[3]
PACKAGE = ROOT / 'benchmark/comparison'


def command(*args):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip() or result.stderr.strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stamp', choices=['pure_dart', 'engine', 'flutter', 'quality'])
    args = parser.parse_args()
    if args.stamp:
        environment = PACKAGE / 'results/environment.json'
        env = json.loads(environment.read_text())
        for path, expected in env['input_sha256'].items():
            assert digest(ROOT / path) == expected, f'Input changed during run: {path}'
        result_path = PACKAGE / f'results/{args.stamp}.json'
        data = json.loads(result_path.read_text())
        started = datetime.datetime.fromisoformat(env['run_id'])
        completed = datetime.datetime.fromisoformat(data['timestamp'].replace('Z', '+00:00'))
        assert completed >= started, f'{args.stamp}: stale result predates this run'
        data['run_id'] = env['run_id']
        data['environment_sha256'] = digest(environment)
        result_path.write_text(json.dumps(data, indent=2) + '\n')
        return
    paths = []
    for directory in ['packages/hyphenation/lib', 'packages/flutter_hyphenation/lib',
                      'benchmark/comparison/benchmark', 'benchmark/comparison/assets',
                      'benchmark/comparison/test',
                      'benchmark/comparison/tool']:
        paths.extend(p for p in (ROOT / directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    paths.extend(PACKAGE / name for name in ['pubspec.yaml', 'pubspec.lock', 'run.sh'])
    data = {
        'run_id': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'git_commit': command('git', 'rev-parse', 'HEAD'),
        'git_dirty': bool(command('git', 'status', '--porcelain')),
        'platform': platform.platform(),
        'architecture': platform.machine(),
        'cpu': command('sysctl', '-n', 'machdep.cpu.brand_string') if platform.system() == 'Darwin' else platform.processor(),
        'dart': command('dart', '--version'),
        'flutter': command('flutter', '--version'),
        'runtime': {'pure_dart': 'Dart VM JIT', 'engine': 'flutter test (debug JIT)', 'flutter': 'flutter test (debug JIT, test font, no GPU raster measurement)'},
        'input_sha256': {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)},
    }
    (PACKAGE / 'results').mkdir(exist_ok=True)
    (PACKAGE / 'results/environment.json').write_text(json.dumps(data, indent=2) + '\n')


if __name__ == '__main__':
    main()
