// VM-service retained-memory workloads. See support/memory_benchmark.py.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_hyphen/src/model/hyphenation_dictionary.dart';

// Global roots outlive the service callback. No introspection getters are used.
final List<HyphenationDictionary> retainedDictionaries = [];
int checksum = 0;

void prepare(String phase) {
  if (phase == 'normal') {
    checksum += retainedDictionaries.single.markWord('hyphenation');
    return;
  }
  retainedDictionaries.clear();
  switch (phase) {
    case 'empty':
      return;
    case 'one':
    case 'twenty':
    case 'giant':
      final bytes = File('example/assets/dictionary/hyph_en_US.dic')
          .readAsBytesSync();
      for (var i = 0; i < (phase == 'twenty' ? 20 : 1); i++) {
        retainedDictionaries.add(HyphenationDictionary.parse(bytes));
      }
      if (phase == 'giant') {
        checksum += retainedDictionaries.single.markWord('x' * 1000000);
      }
      return;
    case 'nohyphen':
      // Small input view backed by an otherwise unreachable 8 MiB parent.
      final parent = Uint8List(8 * 1024 * 1024);
      final source = ascii.encode('UTF-8\nNOHYPHEN -\na1b\n');
      parent.setRange(0, source.length, source);
      retainedDictionaries.add(
        HyphenationDictionary.parse(
          Uint8List.sublistView(parent, 0, source.length),
        ),
      );
      return;
    default:
      throw ArgumentError.value(phase, 'phase');
  }
}

void main() {
  developer.registerExtension('ext.memory.prepare', (method, parameters) async {
    prepare(parameters['phase']!);
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'phase': parameters['phase'],
        'retainedDictionaries': retainedDictionaries.length,
        'checksum': checksum,
      }),
    );
  });
  print('MEMORY_BENCHMARK_READY');
  stdin.listen((_) {});
}
