import 'package:flutter/material.dart';

class PageHelperText extends StatelessWidget {
  const PageHelperText({
    super.key,
    required this.text,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 8),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
      ),
    );
  }
}
