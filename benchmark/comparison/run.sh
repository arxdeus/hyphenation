#!/usr/bin/env bash
# Serial, pinned comparison. Run with an otherwise idle machine.
# Results describe this runtime and workload, not universal ratios or device FPS.
set -euo pipefail
cd "$(dirname "$0")"

echo '==> Resolve the committed dependency lockfile'
flutter pub get --enforce-lockfile

echo '==> Validate fixture equivalence and measurement invariants'
flutter test --no-pub --concurrency=1 test
python3 -m unittest discover -s tool -p '*_test.py'

echo '==> Record runtime, fixture and source identities'
python3 tool/environment.py

echo '==> Pure Dart suite (standalone VM JIT)'
dart run benchmark/pure_dart_comparison.dart
python3 tool/environment.py --stamp pure_dart

echo '==> Engine suite (Flutter debug test runtime)'
flutter test --no-pub --concurrency=1 benchmark/engine_comparison.dart
python3 tool/environment.py --stamp engine

echo '==> Widget suite (test binding, not device FPS)'
flutter test --no-pub --concurrency=1 benchmark/flutter_comparison.dart
python3 tool/environment.py --stamp flutter

echo '==> Output agreement and structural assertions (not an oracle)'
flutter test --no-pub --concurrency=1 benchmark/quality_comparison.dart
python3 tool/environment.py --stamp quality

echo '==> Regenerate comparison and our loss register from these results'
python3 tool/report.py
python3 tool/report.py --check
