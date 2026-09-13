// Routing recoverable hyphenation failures through FlutterError.
//
// `package:hyphenate` prints them instead, having no framework to report to.
// In a Flutter app they should look like every other framework error.

import 'package:flutter/foundation.dart';
import 'package:hyphenate/hyphenate.dart';

final bool _installed = () {
  reportHyphenationError = (Object error, StackTrace stackTrace, String ctx) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'flutter_hyphenation',
        context: ErrorDescription(ctx),
      ),
    );
  };
  return true;
}();

/// Installs the [FlutterError]-based reporter for `package:hyphenate`.
///
/// Called by [HyphenText] and [HyphenationRegistry]; there is no need to call
/// it by hand, and calling it twice is harmless.
void ensureFlutterHyphenationErrorReporting() {
  // Reading the lazy final is what installs it, in every build mode.
  if (_installed) {
    return;
  }
}
