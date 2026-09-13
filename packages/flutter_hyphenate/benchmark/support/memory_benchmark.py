#!/usr/bin/env python3
"""Standard-library Dart VM HTTP driver, no packages required.

python3 benchmark/support/memory_benchmark.py --root . --output /path/result.json
Copy identical harness files into a baseline snapshot before comparing.
Its package_config.json MUST resolve flutter_hyphenate to that snapshot.

Stale: it drives benchmark/memory_benchmark.dart and an example .dic file,
neither of which is in the repository. Kept for the measurement protocol it
records; restore those two inputs before expecting it to run.
Direct Dart invocation avoids dependency resolution. Each phase gets two full
GCs via getAllocationProfile, then getMemoryUsage. This is isolate live heap,
not dominator retained size or RSS. JIT/service overhead can affect phase deltas.
"""
import argparse
import hashlib
import json
import pathlib
import queue
import re
import subprocess
import threading
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='.')
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--output', required=True)
    parser.add_argument('--source-label', help='Snapshot revision when no .git exists')
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve()
    config = root / '.dart_tool/package_config.json'
    packages = json.loads(config.read_text())['packages']
    own = next(p for p in packages if p['name'] == 'flutter_hyphenate')
    resolved = urllib.parse.urljoin(config.as_uri(), own['rootUri'])
    if pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(resolved).path)).resolve() != root:
        raise SystemExit('Package configuration points outside snapshot: ' + resolved)
    def source_hash():
        digest = hashlib.sha256()
        for file in sorted((root / 'lib').rglob('*.dart')):
            digest.update(str(file.relative_to(root)).encode())
            digest.update(file.read_bytes())
        return digest.hexdigest()
    result = {'root': str(root), 'lib_sha256': source_hash(),
              'source_label': args.source_label,
              'harness_sha256': hashlib.sha256((root / 'benchmark/memory_benchmark.dart').read_bytes()).hexdigest(),
              'dictionary_sha256': hashlib.sha256((root / 'example/assets/dictionary/hyph_en_US.dic').read_bytes()).hexdigest(),
              'dart': subprocess.check_output([args.dart, '--version'], text=True).strip(),
              'phases': []}
    try:
        result['git_head'] = subprocess.check_output(
            ['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True,
            stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        result['git_head'] = None
    command = [args.dart, '--enable-vm-service=0/127.0.0.1',
               '--packages=' + str(config), 'benchmark/memory_benchmark.dart']
    process = subprocess.Popen(command, cwd=root, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    lines = queue.Queue()
    def read_lines():
        for line in process.stdout:
            lines.put(line)
        lines.put(None)
    threading.Thread(target=read_lines, daemon=True).start()
    try:
        url = None
        ready = False
        while not (url and ready):
            line = lines.get(timeout=60)
            if line is None:
                raise RuntimeError('Dart exited before readiness')
            print(line.rstrip(), flush=True)
            match = re.search(r'http://127\.0\.0\.1:\d+/[^\s]*/', line)
            if match and 'Dart VM service' in line:
                url = match.group(0)
            ready |= 'MEMORY_BENCHMARK_READY' in line
        def rpc(method, **params):
            request = url + method + '?' + urllib.parse.urlencode(params)
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.load(response)
            if 'error' in payload:
                raise RuntimeError(payload['error'])
            return payload['result']
        isolate = next(i['id'] for i in rpc('getVM')['isolates'] if i['name'] == 'main')
        phases = ['empty', 'one', 'twenty', 'giant', 'normal', 'nohyphen', 'empty']
        # Compile/exercise every workload before the empty baseline. No warmup
        # dictionaries survive the final clear, confirmed by allocation counts.
        for phase in phases:
            rpc('ext.memory.prepare', isolateId=isolate, phase=phase)
        for phase in phases:
            workload = rpc('ext.memory.prepare', isolateId=isolate, phase=phase)
            rpc('getAllocationProfile', isolateId=isolate, gc='true')
            profile = rpc('getAllocationProfile', isolateId=isolate, gc='true')
            memory = rpc('getMemoryUsage', isolateId=isolate)
            members = [{'class': m['class']['name'], 'instances': m['instancesCurrent'],
                        'bytes': m['bytesCurrent']} for m in profile['members']
                       if m.get('bytesCurrent', 0)]
            members.sort(key=lambda m: m['bytes'], reverse=True)
            live_dictionaries = sum(m['instances'] for m in members
                                    if m['class'] == 'HyphenationDictionary')
            expected = 0 if phase == 'empty' else (20 if phase == 'twenty' else 1)
            if live_dictionaries != expected:
                raise RuntimeError(f'{phase}: expected {expected} live dictionaries, got {live_dictionaries}')
            result['phases'].append({'phase': phase, 'workload': workload,
                                    'memory': memory, 'classes': members,
                                    'profile_memory': profile.get('memoryUsage')})
            print(json.dumps({'phase': phase, **memory}), flush=True)
        result['source_unchanged'] = source_hash() == result['lib_sha256']
        pathlib.Path(args.output).write_text(json.dumps(result, indent=2) + '\n')
        if not result['source_unchanged']:
            raise RuntimeError('Library source changed during measurement. Rerun on stable source.')
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


if __name__ == '__main__':
    main()
