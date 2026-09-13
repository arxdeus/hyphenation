/// Where the package reports non-fatal errors.
///
/// A pattern set that cannot hyphenate one word must never take down the
/// caller, so the word is simply left unbroken and the failure is reported
/// here. The default prints to the console.
///
/// `package:flutter_hyphenation` replaces this with `FlutterError.reportError`,
/// so in a Flutter app the failure shows up the way every other framework
/// error does.
library;

/// Signature of the hyphenation error reporter.
typedef HyphenationErrorReporter =
    void Function(Object error, StackTrace stackTrace, String context);

/// The reporter used for recoverable failures. See the library docs.
HyphenationErrorReporter reportHyphenationError = _defaultReporter;

void _defaultReporter(Object error, StackTrace stackTrace, String context) {
  // ignore: avoid_print
  print('hyphenation: $context: $error\n$stackTrace');
}
