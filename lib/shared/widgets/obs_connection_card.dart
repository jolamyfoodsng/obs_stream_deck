import 'package:flutter/material.dart';

import '../../domain/entities/connection_status.dart';

class ObsConnectionCard extends StatelessWidget {
  const ObsConnectionCard({
    super.key,
    required this.status,
    required this.message,
  });

  final ConnectionStatus status;
  final String message;

  Color _statusColor(ColorScheme scheme) {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return scheme.primary;
      case ConnectionStatus.wrongPassword:
      case ConnectionStatus.notFound:
      case ConnectionStatus.error:
        return scheme.error;
      case ConnectionStatus.disconnected:
        return scheme.outline;
    }
  }

  IconData _statusIcon() {
    switch (status) {
      case ConnectionStatus.connected:
        return Icons.check_circle;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return Icons.sync;
      case ConnectionStatus.wrongPassword:
        return Icons.lock_outline;
      case ConnectionStatus.notFound:
        return Icons.search_off;
      case ConnectionStatus.error:
        return Icons.error_outline;
      case ConnectionStatus.disconnected:
        return Icons.link_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(Theme.of(context).colorScheme);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          Icon(_statusIcon(), color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
