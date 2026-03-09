import 'package:flutter/material.dart';

class ProBadge extends StatelessWidget {
  const ProBadge({
    super.key,
    this.label = 'PRO',
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFEAB308);
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF1F2937),
          fontWeight: FontWeight.w800,
          fontSize: compact ? 10 : 11,
          letterSpacing: 0.4,
        );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: gold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: textStyle),
    );
  }
}
