import 'package:flutter/material.dart';

class DemoColumn extends StatelessWidget {
  const DemoColumn({
    required this.title,
    required this.subtitle,
    required this.width,
    required this.child,
  });

  final String title;
  final String subtitle;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium),
        Text(subtitle, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Container(
          width: width,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ],
    );
  }
}
