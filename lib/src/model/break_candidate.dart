// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'package:flutter/foundation.dart';

/// One break opportunity inside a hard line.
@immutable
class BreakCandidate {
  const BreakCandidate({
    required this.end,
    required this.next,
    required this.hyphen,
  });

  /// Offset just past the last character that stays on the line.
  final int end;

  /// Offset at which the following line starts.
  final int next;

  /// Whether a hyphen has to be painted at the end of the line.
  final bool hyphen;
}
