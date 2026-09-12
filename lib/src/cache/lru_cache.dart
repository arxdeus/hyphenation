/// A bounded least-recently-used cache with an optional estimated-weight bound.
///
/// Repeated reads of the most recently used entry do not mutate the map.
/// Other hits move their entry to the end of Dart's insertion-ordered map.
class LruCache<K, V extends Object> {
  /// A zero [maxSize] or [maxWeight] disables caching. Weights are caller-defined
  /// estimates, not measurements of VM heap usage.
  LruCache(this.maxSize, {this.maxWeight})
    : assert(maxSize >= 0, 'maxSize must not be negative'),
      assert(maxWeight == null || maxWeight >= 0);

  final int maxSize;
  final int? maxWeight;
  final Map<K, V> _entries = <K, V>{};
  late final Map<K, int>? _weights = maxWeight == null ? null : <K, int>{};
  int _weight = 0;
  K? _lastKey;
  V? _lastValue;

  int get length => _entries.length;

  /// Total admitted weight, or zero when weight tracking is disabled.
  int get estimatedWeight => _weight;

  bool get isEnabled => maxSize > 0 && maxWeight != 0;

  V? operator [](K key) {
    if (!isEnabled) return null;
    final last = _lastValue;
    if (last != null && (identical(key, _lastKey) || key == _lastKey)) {
      return last;
    }
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    _lastKey = key;
    _lastValue = value;
    return value;
  }

  void operator []=(K key, V value) => put(key, value);

  /// Stores a value, evicting oldest entries until both bounds are satisfied.
  /// An oversized entry is not admitted and does not evict unrelated entries.
  /// Replacing an entry with an oversized value removes its old cached value.
  void put(K key, V value, {int weight = 1}) {
    assert(weight >= 0);
    if (!isEnabled) return;
    _entries.remove(key);
    final weights = _weights;
    if (weights != null) _weight -= weights.remove(key) ?? 0;
    _lastKey = null;
    _lastValue = null;
    final bound = maxWeight;
    if (bound != null && weight > bound) return;
    while (_entries.length >= maxSize ||
        (bound != null && _weight + weight > bound)) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
      if (weights != null) _weight -= weights.remove(oldest)!;
    }
    _entries[key] = value;
    if (weights != null) {
      weights[key] = weight;
      _weight += weight;
    }
    _lastKey = key;
    _lastValue = value;
  }

  void clear() {
    _entries.clear();
    _weights?.clear();
    _weight = 0;
    _lastKey = null;
    _lastValue = null;
  }
}
