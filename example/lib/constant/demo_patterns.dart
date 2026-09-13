import 'package:flutter_hyphen/flutter_hyphen.dart';

/// The English pattern file bundled with this example.
///
/// This is Knuth's Plain TeX pattern set, distributed by CTAN as
/// `ushyph1.tex`. Other languages live in the hyph-utf8 collection. See the
/// package README.
const String kEnglishPatterns = 'assets/patterns/ushyph1.tex';

/// The same patterns without the dangling-word list, for the demo toggle.
///
/// It shares the compiled pattern set with the registered one, so the file is
/// only read and compiled once.
late final Hyphenator kPlainHyphenator;
