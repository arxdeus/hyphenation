import 'measure.dart';

double? _finite(double value) => value.isFinite ? value : null;

/// One scenario: the same work, measured through every package.
class ComparisonRow {
  ComparisonRow({
    required this.name,
    required this.units,
    required this.unitCount,
    required this.results,
    this.note,
  });

  /// What was measured.
  final String name;

  /// What one operation covers: `words`, `chars`, `frames`.
  final String units;

  /// How many [units] one operation covers, for the throughput column.
  final int unitCount;

  /// Results keyed by package name. The baseline is the first key.
  final Map<String, Measurement> results;

  /// Anything the reader needs in order not to misread the row.
  final String? note;

  /// The package every ratio is taken against.
  String get baselineName => results.keys.first;

  Measurement get baseline => results[baselineName]!;

  /// Ratio of [package]'s mean to the baseline's, with a 95% interval.
  RatioInterval intervalFor(String package) =>
      RatioInterval.compute(results[package]!, baseline);

  /// Median time for one operation, in microseconds.
  double medianUs(String package) => results[package]!.medianNs / 1000;

  /// Units processed per second by [package].
  double unitsPerSecond(String package) =>
      unitCount / (results[package]!.medianNs / 1e9);

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'units': units,
    'unit_count': unitCount,
    'baseline': baselineName,
    if (note != null) 'note': note,
    'packages': <String, Object?>{
      for (final entry in results.entries)
        entry.key: <String, Object?>{
          'median_ns': entry.value.medianNs,
          'mean_ns': entry.value.meanNs,
          'stddev_ns': entry.value.stddevNs,
          'cv': entry.value.cv,
          'batch_size': entry.value.batchSize,
          'trials': entry.value.trialsNs.length,
          'trials_ns': entry.value.trialsNs,
          'median_us': medianUs(entry.key),
          'units_per_second': unitsPerSecond(entry.key),
          if (entry.key != baselineName) ...<String, Object?>{
            'ratio_to_baseline': _finite(intervalFor(entry.key).ratio),
            'ratio_ci_valid': intervalFor(entry.key).isValid,
            'ratio_ci_low': _finite(intervalFor(entry.key).low),
            'ratio_ci_high': _finite(intervalFor(entry.key).high),
          },
        },
    },
  };
}

/// Collects rows and renders the table printed at the end of a suite.
class ComparisonReport {
  ComparisonReport(this.title);

  /// Which suite this is: `engine` or `flutter`.
  final String title;

  /// The rows, in the order they were measured.
  final List<ComparisonRow> rows = <ComparisonRow>[];

  /// What each package returned for a reference input, so that a package
  /// which is fast because it does less is not mistaken for one that is fast.
  final Map<String, String> outputs = <String, String>{};

  void add(ComparisonRow row) => rows.add(row);

  /// A number formatted so that both 0.012 and 232664 stay readable.
  static String _us(double value) {
    if (value >= 1000) return value.toStringAsFixed(0);
    if (value >= 10) return value.toStringAsFixed(2);
    return value.toStringAsFixed(4);
  }

  /// A ratio formatted the same way, since they span six orders of magnitude.
  static String ratioLabel(double value) {
    if (value.isNaN) return 'n/a';
    if (value >= 1000) return '${value.toStringAsFixed(0)}x';
    if (value >= 10) return '${value.toStringAsFixed(1)}x';
    return '${value.toStringAsFixed(2)}x';
  }

  /// The table, as printed to the console at the end of the run.
  String render() {
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('=' * 88)
      ..writeln(
        '  $title comparison   (median us/op, ratio vs baseline, '
        'Fieller 95% CI)',
      )
      ..writeln('=' * 88);
    for (final row in rows) {
      buffer
        ..writeln()
        ..writeln('${row.name}  (${row.unitCount} ${row.units}/op)')
        ..writeln(
          '${'package'.padRight(22)}${'us/op'.padLeft(12)}'
          '${'${row.units}/s'.padLeft(14)}${'vs baseline'.padLeft(13)}'
          '${'95% CI'.padLeft(20)}',
        )
        ..writeln('-' * 81);
      for (final package in row.results.keys) {
        final isBaseline = package == row.baselineName;
        final ratio = isBaseline ? null : row.intervalFor(package);
        final ci = ratio == null
            ? ''
            : ratio.isValid
            ? '[${ratioLabel(ratio.low)}, ${ratioLabel(ratio.high)}]'
            : 'n/a';
        buffer.writeln(
          '${package.padRight(22)}'
          '${_us(row.medianUs(package)).padLeft(12)}'
          '${row.unitsPerSecond(package).toStringAsFixed(0).padLeft(14)}'
          '${(isBaseline ? 'baseline' : ratioLabel(ratio!.ratio)).padLeft(13)}'
          '${ci.padLeft(20)}',
        );
      }
      if (row.note != null) {
        buffer.writeln('  note: ${row.note}');
      }
    }
    if (outputs.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Output for the reference word:');
      for (final entry in outputs.entries) {
        buffer.writeln('  ${entry.key.padRight(22)}${entry.value}');
      }
    }
    buffer
      ..writeln()
      ..writeln(
        'Lower us/op is better. A ratio above 1 means the package is '
        'slower than the baseline.',
      )
      ..writeln('=' * 88);
    return buffer.toString();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'suite': title,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'reference_outputs': outputs,
    'rows': <Object?>[for (final row in rows) row.toJson()],
  };
}
