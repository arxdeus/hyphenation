import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text style every layout benchmark paints with.
const TextStyle kStyle = TextStyle(fontSize: 16, height: 1.3);

/// Builds the widget under test inside a fixed-width column.
Widget buildHost(Widget child, double width) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: SizedBox(width: width, child: child),
  ),
);

/// Attaches [widget] to the tree and pumps one frame, synchronously.
///
/// `WidgetTester.pumpWidget` is async and guarded, so bench_press cannot call
/// it from a synchronous benchmark body. Driving the binding directly does the
/// same work, and has the side benefit of measuring only build plus layout
/// plus paint, without the test framework's bookkeeping.
void pumpSync(WidgetTester tester, Widget widget) {
  // The same steps `pumpWidget` takes, minus its async guard: the widget has
  // to be wrapped in the binding's default View or the render tree has no root
  // to attach to.
  tester.binding.attachRootWidget(tester.binding.wrapWithDefaultView(widget));
  tester.binding.scheduleFrame();
  tester.binding.handleBeginFrame(null);
  tester.binding.handleDrawFrame();
}
