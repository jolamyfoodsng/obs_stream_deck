import 'dart:convert';

class ObsQrPayload {
  const ObsQrPayload({
    required this.host,
    required this.port,
    required this.password,
    this.label,
  });

  final String host;
  final int port;
  final String password;
  final String? label;
}

class ObsQrPayloadParser {
  const ObsQrPayloadParser._();

  static ObsQrPayload parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const FormatException('Empty QR payload.');
    }

    final fromJson = _tryParseJson(value);
    if (fromJson != null) return fromJson;

    final fromUri = _tryParseUri(value);
    if (fromUri != null) return fromUri;

    throw const FormatException(
      'Unsupported QR format. Expected JSON with host/port/password.',
    );
  }

  static ObsQrPayload? _tryParseJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final map = decoded.cast<String, dynamic>();
      final host = (map['host'] as String?)?.trim() ?? '';
      if (host.isEmpty) return null;

      final parsedPort = _parsePort(map['port']);
      if (parsedPort == null) return null;

      return ObsQrPayload(
        host: host,
        port: parsedPort,
        password: (map['password'] as String?) ?? '',
        label: (map['label'] as String?) ?? (map['device'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  static ObsQrPayload? _tryParseUri(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;

    final isSupportedScheme = uri.scheme == 'obsdeck' ||
        uri.scheme == 'obs' ||
        uri.scheme == 'obsws' ||
        uri.scheme == 'ws' ||
        uri.scheme == 'wss';
    if (!isSupportedScheme) return null;

    final host = uri.host.trim();
    if (host.isEmpty) return null;

    final parsedPort = uri.hasPort
        ? uri.port
        : _parsePort(uri.queryParameters['port']) ?? 4455;
    if (parsedPort < 1 || parsedPort > 65535) return null;

    final password = uri.queryParameters['password'] ?? '';
    final label = uri.queryParameters['label'] ?? uri.queryParameters['device'];

    return ObsQrPayload(
      host: host,
      port: parsedPort,
      password: password,
      label: label,
    );
  }

  static int? _parsePort(Object? portValue) {
    if (portValue is int) {
      return (portValue >= 1 && portValue <= 65535) ? portValue : null;
    }
    if (portValue is String) {
      final parsed = int.tryParse(portValue.trim());
      if (parsed == null) return null;
      return (parsed >= 1 && parsed <= 65535) ? parsed : null;
    }
    return null;
  }
}
