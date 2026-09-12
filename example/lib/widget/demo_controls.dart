import 'package:flutter/material.dart';

class DemoControls extends StatelessWidget {
  const DemoControls({
    required this.width,
    required this.fontSize,
    required this.justify,
    required this.onWidth,
    required this.onFontSize,
    required this.onJustify,
    required this.noDangling,
    required this.onNoDangling,
  });

  final double width;
  final double fontSize;
  final bool justify;
  final ValueChanged<double> onWidth;
  final ValueChanged<double> onFontSize;
  final ValueChanged<bool> onJustify;
  final bool noDangling;
  final ValueChanged<bool> onNoDangling;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const SizedBox(width: 80, child: Text('Width')),
                Expanded(
                  child: Slider(
                    value: width,
                    min: 80,
                    max: 400,
                    onChanged: onWidth,
                  ),
                ),
                Text(width.round().toString()),
              ],
            ),
            Row(
              children: <Widget>[
                const SizedBox(width: 80, child: Text('Font size')),
                Expanded(
                  child: Slider(
                    value: fontSize,
                    min: 10,
                    max: 40,
                    onChanged: onFontSize,
                  ),
                ),
                Text(fontSize.round().toString()),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Justify'),
              value: justify,
              onChanged: onJustify,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('No hanging prepositions'),
              subtitle: const Text('never break after a short word'),
              value: noDangling,
              onChanged: onNoDangling,
            ),
          ],
        ),
      ),
    );
  }
}
