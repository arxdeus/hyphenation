// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

/// A map that keeps at most [maxSize] entries and discards the least recently
/// used one when it overflows.
///
/// The caches in this package live for as long as the [Hyphenator] does, which
/// in a normal app means for as long as the app does. They therefore need a
/// bound, and the bound has to evict by use rather than by insertion order: a
/// paragraph that is on screen every frame must not be thrown out because it
/// happened to be cached first.
///
/// Recency is tracked by Dart's map iteration order, which is insertion order:
/// reading an entry removes and reinserts it, moving it to the end, so the
/// first key is always the least recently used one.
class LruCache<K, V extends Object> {
  /// Creates a cache holding at most [maxSize] entries.
  ///
  /// A [maxSize] of zero disables caching entirely.
  LruCache(this.maxSize) : assert(maxSize >= 0, 'maxSize must not be negative');

  /// The most entries this cache will hold.
  final int maxSize;

  final Map<K, V> _entries = <K, V>{};

  /// How many entries are currently held.
  int get length => _entries.length;

  /// The value for [key], or null when absent. Marks the entry as used.
  V? operator [](K key) {
    final value = _entries.remove(key);
    if (value == null) {
      return null;
    }
    _entries[key] = value;
    return value;
  }

  /// Stores [value] under [key], evicting the least recently used entry when
  /// the cache is full.
  void operator []=(K key, V value) {
    if (maxSize <= 0) {
      return;
    }
    // Remove first, so that overwriting an existing key also refreshes its
    // position instead of leaving the stale one at the front.
    _entries.remove(key);
    if (_entries.length >= maxSize) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = value;
  }

  /// Removes every entry.
  void clear() => _entries.clear();
}
