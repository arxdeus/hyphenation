import 'package:meta/meta.dart';

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
