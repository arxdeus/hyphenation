import 'dart:math' as math;

/// Retains output in observable state, without timing a deep hash.
class Blackhole {
  static Object? value;
  @pragma('vm:never-inline')
  // ignore: use_setters_to_change_properties
  static void consume(Object? result) {
    value = result;
  }
}

/// Per-operation timings from calibrated batches.
class Measurement {
  Measurement(this.name, this.trialsNs, this.batchSize);

  /// The package measured.
  final String name;

  /// Nanoseconds per operation, one entry per trial.
  final List<double> trialsNs;

  /// Operations executed per timed trial.
  final int batchSize;

  /// Median nanoseconds per operation.
  late final double medianNs = _percentile(50);

  /// Mean nanoseconds per operation.
  late final double meanNs = trialsNs.reduce((a, b) => a + b) / trialsNs.length;

  /// Sample standard deviation across trials.
  late final double stddevNs = () {
    if (trialsNs.length < 2) return 0.0;
    final mean = meanNs;
    final sum = trialsNs
        .map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b);
    return math.sqrt(sum / (trialsNs.length - 1));
  }();

  /// Coefficient of variation, the usual "is this trustworthy" check.
  double get cv => meanNs == 0 ? 0 : stddevNs / meanNs;

  double _percentile(int p) {
    final sorted = List<double>.from(trialsNs)..sort();
    if (sorted.length == 1) return sorted.first;
    final rank = (p / 100) * (sorted.length - 1);
    final low = rank.floor();
    final high = rank.ceil();
    if (low == high) return sorted[low];
    return sorted[low] + (sorted[high] - sorted[low]) * (rank - low);
  }
}

/// Calibrates batches, warms up, then retains every timed trial.
/// Warmup reduces JIT effects but cannot prove compilation has settled.
Measurement measure(
  String name,
  void Function() body, {
  int trials = 10,
  Duration targetBatchDuration = const Duration(milliseconds: 50),
  Duration warmupBudget = const Duration(milliseconds: 300),
  int maxCalibrationIterations = 1 << 22,
}) {
  if (trials < 1 || maxCalibrationIterations < 1) {
    throw ArgumentError('trials and calibration cap must be positive');
  }
  // Calibrate: double the batch until a batch reaches the target, capping so
  // a pathologically fast body cannot spin forever.
  var batch = 1;
  var batchNs = 0;
  final targetNs = targetBatchDuration.inMicroseconds * 1000;
  final watch = Stopwatch();
  while (batch <= maxCalibrationIterations) {
    watch
      ..reset()
      ..start();
    for (var i = 0; i < batch; i++) {
      body();
    }
    watch.stop();
    batchNs = watch.elapsedMicroseconds * 1000;
    if (batchNs >= targetNs || batch == maxCalibrationIterations) break;
    // A zero-duration batch carries no information about the right size, so
    // step it up aggressively rather than doubling from noise.
    batch = math.min(
      maxCalibrationIterations,
      batchNs == 0 ? batch * 16 : batch * 2,
    );
  }

  // Warm up for a fixed wall-clock budget rather than a fixed count, which
  // would be either pointless for a slow package or endless for a fast one.
  final warmup = Stopwatch()..start();
  while (warmup.elapsed < warmupBudget) {
    for (var i = 0; i < batch; i++) {
      body();
    }
  }
  warmup.stop();

  final results = <double>[];
  for (var trial = 0; trial < trials; trial++) {
    watch
      ..reset()
      ..start();
    for (var i = 0; i < batch; i++) {
      body();
    }
    watch.stop();
    results.add(watch.elapsedTicks * 1e9 / watch.frequency / batch);
  }
  return Measurement(name, results, batch);
}

/// Ratio of means with an approximate Fieller 95% interval.
/// Assumes independent, approximately normal trial means. Serial VM timings
/// may violate those assumptions, so intervals are descriptive, not guarantees.
class RatioInterval {
  const RatioInterval(this.ratio, this.low, this.high, {required this.isValid});

  /// Point estimate: mean of the candidate over mean of the baseline.
  final double ratio;

  /// Lower bound of the 95% interval.
  final double low;

  /// Upper bound of the 95% interval.
  final double high;

  /// False when the denominator is too noisy for a bounded interval, which
  /// or there are insufficient observations.
  final bool isValid;

  /// Computes the interval for [candidate] relative to [baseline].
  factory RatioInterval.compute(Measurement candidate, Measurement baseline) {
    final a = candidate.meanNs;
    final b = baseline.meanNs;
    final ratio = b == 0 ? double.nan : a / b;
    final na = candidate.trialsNs.length;
    final nb = baseline.trialsNs.length;
    if (na < 2 || nb < 2 || b <= 0 || !a.isFinite || !b.isFinite) {
      return RatioInterval(ratio, double.nan, double.nan, isValid: false);
    }
    final va = candidate.stddevNs * candidate.stddevNs / na;
    final vb = baseline.stddevNs * baseline.stddevNs / nb;
    // Two-sided 95% critical value at the smaller sample's degrees of
    // freedom, which is the conservative choice for the Welch-style pooling
    // used here.
    final t = _tCritical95(math.min(na, nb) - 1);
    final g = t * t * vb / (b * b);
    if (g >= 1) {
      // Fieller's g >= 1 means the denominator's interval spans zero and the
      // ratio is unbounded. Reported rather than hidden behind a number.
      return RatioInterval(ratio, double.nan, double.nan, isValid: false);
    }
    final centre = ratio / (1 - g);
    final discriminant = va + ratio * ratio * vb - g * va;
    if (discriminant < 0) {
      return RatioInterval(ratio, double.nan, double.nan, isValid: false);
    }
    final halfWidth = t / (b * (1 - g)) * math.sqrt(discriminant);
    return RatioInterval(
      ratio,
      centre - halfWidth,
      centre + halfWidth,
      isValid: true,
    );
  }
}

/// Student's t at 97.5% for small degrees of freedom, with a normal tail.
double _tCritical95(int df) {
  const table = <int, double>{
    1: 12.706,
    2: 4.303,
    3: 3.182,
    4: 2.776,
    5: 2.571,
    6: 2.447,
    7: 2.365,
    8: 2.306,
    9: 2.262,
    10: 2.228,
    11: 2.201,
    12: 2.179,
    13: 2.160,
    14: 2.145,
    15: 2.131,
    20: 2.086,
    30: 2.042,
  };
  if (table.containsKey(df)) return table[df]!;
  if (df < 1) return double.infinity;
  if (df > 30) return 1.96;
  // Between tabulated points, take the next lower df: conservative.
  final keys = table.keys.where((k) => k < df).toList()..sort();
  return table[keys.last]!;
}

/// Calibrate separately, then rotate candidate order across timed trials.
Map<String, Measurement> measureGroup(
  Map<String, void Function()> bodies, {
  int trials = 10,
  Duration targetBatchDuration = const Duration(milliseconds: 50),
  Duration warmupBudget = const Duration(milliseconds: 300),
  int maxCalibrationIterations = 1 << 22,
}) {
  if (trials < 1 || bodies.isEmpty) throw ArgumentError('empty measurement');
  final keys = bodies.keys.toList();
  final batches = <String, int>{};
  final samples = <String, List<double>>{};
  for (final key in keys) {
    batches[key] = measure(
      key,
      bodies[key]!,
      trials: 1,
      targetBatchDuration: targetBatchDuration,
      warmupBudget: warmupBudget,
      maxCalibrationIterations: maxCalibrationIterations,
    ).batchSize;
    samples[key] = [];
  }
  // Fixed shared prewarm policy, not post-hoc removal of slow trials.
  for (var round = 0; round < 3; round++) {
    for (var offset = 0; offset < keys.length; offset++) {
      final key = keys[(round + offset) % keys.length];
      for (var i = 0; i < batches[key]!; i++) {
        bodies[key]!();
      }
    }
  }
  for (var trial = 0; trial < trials; trial++) {
    for (var offset = 0; offset < keys.length; offset++) {
      final key = keys[(trial + offset) % keys.length];
      final body = bodies[key]!;
      final batch = batches[key]!;
      final watch = Stopwatch()..start();
      for (var i = 0; i < batch; i++) {
        body();
      }
      watch.stop();
      samples[key]!.add(watch.elapsedTicks * 1e9 / watch.frequency / batch);
    }
  }
  return {
    for (final key in keys) key: Measurement(key, samples[key]!, batches[key]!),
  };
}
