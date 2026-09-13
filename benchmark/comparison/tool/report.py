#!/usr/bin/env python3
"""Generate comparison and loss reports only from checked-in measurement data."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[3]
RESULTS = ROOT / 'benchmark/comparison/results'


def load(name):
    return json.loads((RESULTS / name).read_text())


def number(value):
    if value is None or not math.isfinite(value):
        return 'n/a'
    return f'{value:,.3f}' if abs(value) >= 1 else f'{value:.5f}'


def cell(value):
    return str(value).replace('|', '\\|').replace('\n', ' ')


def raw(value):
    for key in ('raw_trials_ns', 'trials_ns', 'raw_trial_latencies_ns'):
        if key in value:
            return value[key]
    raise ValueError('No raw trials persisted')


def validate(suite):
    for row in suite['rows']:
        for name, value in row['packages'].items():
            samples = raw(value)
            assert len(samples) >= 2, (name, 'Insufficient trials')
            assert all(math.isfinite(x) and x > 0 for x in samples), (name, samples)
            assert math.isclose(statistics.median(samples) / 1000, value['median_us'], rel_tol=1e-9)
            assert math.isclose(statistics.mean(samples), value['mean_ns'], rel_tol=1e-9)


def ratio_interval(a, b):
    """Conservative Fieller interval for independent trial means, a/b."""
    aa, bb = raw(a), raw(b)
    am, bm = statistics.mean(aa), statistics.mean(bb)
    va, vb = statistics.variance(aa) / len(aa), statistics.variance(bb) / len(bb)
    df = min(len(aa), len(bb)) - 1
    critical = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571,
                6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228,
                15: 2.131, 20: 2.086, 30: 2.042}
    t = critical[max(k for k in critical if k <= df)]
    g = t * t * vb / (bm * bm)
    if g >= 1:
        return am / bm, None, None
    ratio = am / bm
    centre = ratio / (1 - g)
    half = t * math.sqrt(max(0, va + ratio * ratio * vb - g * va)) / (bm * (1 - g))
    return ratio, centre - half, centre + half


def matrix(suite, names):
    lines = ['| Workload | ' + ' | '.join(names.values()) + ' |',
             '| --- | ' + ' | '.join('---:' for _ in names) + ' |']
    for row in suite['rows']:
        values = []
        for name in names:
            value = row['packages'].get(name)
            values.append('—' if value is None else number(value['median_us']) + (' ⚠' if value['cv'] > .05 else ''))
        label = row['name']
        if row['units'] == 'chars':
            label += f" ({row['unit_count']} chars)"
        lines.append('| ' + cell(label) + ' | ' + ' | '.join(values) + ' |')
    return lines + ['']


def main():
    import re
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--from-recorded', action='store_true',
                        help='Reformat manifest-verified historical results without claiming current source identity')
    args = parser.parse_args()
    suites = {name: load(f'{name}.json') for name in ('pure_dart', 'engine', 'flutter')}
    quality, env = load('quality.json'), load('environment.json')
    environment_hash = hashlib.sha256((RESULTS / 'environment.json').read_bytes()).hexdigest()
    for data in [*suites.values(), quality]:
        assert data['run_id'] == env['run_id'], 'Results are from mixed runs'
        assert data['environment_sha256'] == environment_hash, 'Result/environment mismatch'
    if args.check or args.from_recorded:
        for name, expected in load('manifest.json').items():
            assert hashlib.sha256((RESULTS / name).read_bytes()).hexdigest() == expected, f'{name}: manifest mismatch'
    else:
        for path, expected in env['input_sha256'].items():
            assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected, f'Input changed: {path}'
    lock_path = 'benchmark/comparison/pubspec.lock'
    assert hashlib.sha256((ROOT / lock_path).read_bytes()).hexdigest() == env['input_sha256'][lock_path]
    lock = (ROOT / lock_path).read_text()
    versions = dict(re.findall(r'^  (\w+):\n(?:(?!^  \w+:)[\s\S])*?^    version: "([^"]+)"', lock, re.M))
    for suite in suites.values():
        validate(suite)
    dart = re.search(r'version: ([\d.]+)', env['dart']).group(1)
    flutter = re.search(r'Flutter ([\d.]+)', env['flutter']).group(1)
    doc = ['# Benchmark comparison', '',
           f"Measured {env['run_id'][:10]} · {env['cpu']} · Dart {dart} / Flutter {flutter}.", '',
           '**Median µs per workload, lower is faster.** ⚠ = CV > 5%. Selected pinned packages, not an exhaustive survey.', '',
           '## Pure Dart (VM JIT)', '',
           '| Package | Version | Public import compiles without Flutter |', '| --- | --- | --- |']
    for entry in suites['pure_dart']['portability']:
        package = entry['package']
        version = versions[package] + (' (local)' if package == 'hyphenation' else '')
        status = 'Yes' if entry['plain_dart_compile_succeeded'] else 'No: dart:ui'
        doc.append(f'| {package} | {version} | {status} |')
    doc += ['', 'Only our engine was timed here. Import compilation does not test standalone dependency resolution or runtime behavior.', '']
    doc += matrix(suites['pure_dart'], {'hyphenation': 'hyphenation'})
    doc += ['## Engines (Flutter debug test runtime)', '']
    doc += matrix(suites['engine'], {n: n for n in ('hyphenation', 'hyphenation (cacheSplitParts)', 'hyphenatorx', 'hyphenator_impure', 'hyphen')})
    doc += ['`cacheSplitParts` is an opt-in variant of our engine, not the default: it retains finished part lists per word, as hyphenatorx does, and costs roughly 3.5x the word-cache bytes. A dash means the variant does not apply to that workload.', '']
    doc += ['## Flutter layout (µs per test pump, not device FPS)', '']
    doc += matrix(suites['flutter'], {'flutter_hyphenation': 'flutter_hyphenation (local)',
        'auto_hyphenating_text': 'auto_hyphenating_text', 'hyphenatorx (wrap adapter)': 'hyphenatorx wrap',
        'Text (no hyphens)': 'Text control', 'hyphen (precomputed SHY adapter)': 'hyphen + precomputed SHY'})
    doc += ['Text does not hyphenate. SHY uses precomputed text and a different rendering contract. The x wrap adapter excludes async widget startup.', '',
            '## Where ours loses', '',
            'All lower-median alternatives are included. Ratios use **our mean / their mean**, not medians. Approximate 95% intervals describe local sampling only.', '',
            '| Workload | Faster median alternative | Our mean / theirs (95% interval) | Evidence |',
            '| --- | --- | ---: | --- |']
    for suite_name in ('engine', 'flutter'):
        own = 'hyphenation' if suite_name == 'engine' else 'flutter_hyphenation'
        for row in suites[suite_name]['rows']:
            ours = row['packages'][own]
            for name, other in row['packages'].items():
                if name == own or name.startswith(own) or other['median_us'] >= ours['median_us']:
                    continue
                ratio, low, high = ratio_interval(ours, other)
                ci = f'{low:.3f}–{high:.3f}' if low is not None else 'unbounded'
                evidence = 'Local loss' if low is not None and low > 1 else 'Inconclusive'
                if 'Text' in name or any(tag in name.lower() for tag in ('shy', 'precomputed', 'soft')):
                    evidence += ', different-feature control'
                if max(ours['cv'], other['cv']) > .05:
                    evidence += ' ⚠'
                doc.append(f"| {suite_name}: {row['name']} | {name} | {ratio:.3f}× ({ci}) | {evidence} |")
    doc += ['', 'Setup disadvantage: we require externally sourced dictionaries, while x and impure bundle them. Remaining warm-word deficits are allocation in `split`, which returns fresh parts instead of retaining finished lists per word as hyphenatorx does.', '',
            '## Output agreement (not accuracy)', '',
            f"{quality['corpus_size']} observations, including 1,000 synthetic tokens. More breaks is not necessarily better.", '',
            '| A | B | Identical outputs |', '| --- | --- | ---: |']
    for pair in quality['pairwise_agreement']:
        doc.append(f"| {pair['a']} | {pair['b']} | {pair['words_identical_pct']:.2f}% |")
    doc += ['', '## Conditions', '',
            '- Same English source rules, no exceptions, minima 3/3. Hunspell preprocessing is checked against the official compiler golden. Outputs can still differ.',
            '- Load excludes file I/O and format conversion. Engine cold includes cache reset/front-object allocation, not dictionary parsing. Paragraph adapters share tokenization and reconstruction, without whole-paragraph caching.',
            '- The 2,000-word set is synthetic and fits our cache. Widths cycle through 120 values. Widget cold resets are outside timing. These do not test cache eviction.',
            '- Rotated trials: engines get 300 ms warmup plus three untimed batch rounds, widgets get 2 seconds per candidate plus 240 pumps per trial. All samples retained. Small noisy differences are inconclusive, no multiple-comparison correction.',
            '- Local JIT/debug tests only. No release/device, linguistic accuracy, memory or app-size conclusions.', '']
    target = ROOT / 'BENCHMARK_COMPARSION.md'
    content = '\n'.join(doc)
    if args.check:
        assert target.read_text() == content, 'Report is stale'
    else:
        target.write_text(content)
        if not args.from_recorded:
            manifest = {name: hashlib.sha256((RESULTS / name).read_bytes()).hexdigest()
                        for name in ['engine.json', 'flutter.json', 'pure_dart.json', 'quality.json', 'environment.json']}
            (RESULTS / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Report verified' if args.check else 'Report generated')


if __name__ == '__main__':
    main()
