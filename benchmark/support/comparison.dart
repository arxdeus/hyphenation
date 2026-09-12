// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'package:bench_press/bench_press.dart';

/// One `Text` versus `HyphenText` comparison.
class LayoutComparison {
  LayoutComparison(this.name, this.plain, this.hyphen);

  /// What was compared.
  final String name;

  /// Result for the plain [Text] variant.
  final BenchmarkResult plain;

  /// Result for the [HyphenText] variant.
  final BenchmarkResult hyphen;

  /// Ratio of the means, with a Fieller 95% confidence interval.
  FiellerInterval get interval => FiellerInterval.compute(
    sampleA: hyphen.rawTrialLatenciesNs,
    sampleB: plain.rawTrialLatenciesNs,
  );

  String get row {
    final ratio = interval;
    final plainUs = (plain.metrics.medianNs / 1000).toStringAsFixed(1);
    final hyphenUs = (hyphen.metrics.medianNs / 1000).toStringAsFixed(1);
    final ci = ratio.isValid
        ? '[${ratio.lowerBound.toStringAsFixed(2)}, '
              '${ratio.upperBound.toStringAsFixed(2)}]'
        : 'n/a';
    return '${name.padRight(32)}'
        '${plainUs.padLeft(9)}'
        '${hyphenUs.padLeft(11)}'
        '${'${ratio.ratio.toStringAsFixed(2)}x'.padLeft(8)}'
        '${ci.padLeft(16)}';
  }
}

/// One baseline versus candidate comparison, rendered as a table row.
class ThroughputComparison {
  ThroughputComparison(this.name, this.units, this.baseline, this.candidate);

  /// What was compared.
  final String name;

  /// Characters covered by one operation, for the throughput column.
  final int units;

  /// The slower, or reference, variant.
  final BenchmarkResult baseline;

  /// The variant under test.
  final BenchmarkResult candidate;

  /// Ratio of the means, with a Fieller 95% confidence interval.
  FiellerInterval get interval => FiellerInterval.compute(
    sampleA: candidate.rawTrialLatenciesNs,
    sampleB: baseline.rawTrialLatenciesNs,
  );

  String get row {
    final ratio = interval;
    final baseUs = (baseline.metrics.medianNs / 1000).toStringAsFixed(2);
    final candUs = (candidate.metrics.medianNs / 1000).toStringAsFixed(2);
    final mcps = units / candidate.metrics.medianNs * 1000;
    final ci = ratio.isValid
        ? '[${ratio.lowerBound.toStringAsFixed(2)}, '
              '${ratio.upperBound.toStringAsFixed(2)}]'
        : 'n/a';
    return '${name.padRight(26)}'
        '${units.toString().padLeft(7)}'
        '${baseUs.padLeft(10)}'
        '${candUs.padLeft(10)}'
        '${'${ratio.ratio.toStringAsFixed(2)}x'.padLeft(8)}'
        '${ci.padLeft(16)}'
        '${mcps.toStringAsFixed(0).padLeft(9)}';
  }
}
