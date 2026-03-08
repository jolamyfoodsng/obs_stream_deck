import 'package:flutter/material.dart';

import '../../domain/entities/controller_page.dart';

class PageCard extends StatelessWidget {
  const PageCard({
    super.key,
    required this.page,
    required this.onEdit,
    required this.onDefaultToggle,
  });

  final ControllerPage page;
  final VoidCallback onEdit;
  final VoidCallback onDefaultToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    page.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (page.isDefault)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Default',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${page.columns}x${page.rows} · ${page.buttonCount} buttons'),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: onEdit,
                  child: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onDefaultToggle,
                  child: Text(page.isDefault ? 'Unset Default' : 'Set Default'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
