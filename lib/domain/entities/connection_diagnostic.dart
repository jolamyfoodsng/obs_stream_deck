enum ConnectionDiagnosticSeverity { info, warning, error }

enum ConnectionDiagnosticType {
  setupGuide,
  networkCheck,
  obsNotRunning,
  websocketDisabled,
  wrongPassword,
  firewallBlocked,
  differentNetwork,
  versionMismatch,
  invalidHost,
  networkUnavailable,
  usbGuidance,
  reconnecting,
  connectionHealthy,
  unknown,
}

class ConnectionDiagnostic {
  const ConnectionDiagnostic({
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    required this.fix,
  });

  final ConnectionDiagnosticType type;
  final ConnectionDiagnosticSeverity severity;
  final String title;
  final String message;
  final String fix;
}
