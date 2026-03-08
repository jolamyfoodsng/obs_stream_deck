import 'package:flutter/material.dart';

enum ControllerAlertLevel {
  success,
  warning,
  error,
}

class ControllerAlertBanner {
  const ControllerAlertBanner({
    required this.key,
    required this.message,
    required this.level,
    this.dismissible = true,
    this.autoHideAfter,
  });

  final String key;
  final String message;
  final ControllerAlertLevel level;
  final bool dismissible;
  final Duration? autoHideAfter;

  Color tone(ColorScheme colorScheme) {
    return switch (level) {
      ControllerAlertLevel.success => Colors.green,
      ControllerAlertLevel.warning => Colors.orange,
      ControllerAlertLevel.error => colorScheme.error,
    };
  }

  IconData icon() {
    return switch (level) {
      ControllerAlertLevel.success => Icons.check_circle_outline,
      ControllerAlertLevel.warning => Icons.warning_amber_rounded,
      ControllerAlertLevel.error => Icons.error_outline,
    };
  }
}
