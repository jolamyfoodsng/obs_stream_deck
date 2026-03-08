import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/entities/discovered_obs_device.dart';

class ObsAutoDiscoveryService {
  const ObsAutoDiscoveryService();

  Future<List<DiscoveredObsDevice>> discover({
    Iterable<String> preferredHosts = const <String>[],
    int port = 4455,
    Duration connectTimeout = const Duration(milliseconds: 420),
    Duration helloTimeout = const Duration(milliseconds: 650),
    int maxHosts = 320,
    int batchSize = 36,
  }) async {
    final candidates = await _candidateHosts(
      preferredHosts: preferredHosts,
      maxHosts: maxHosts,
    );
    if (candidates.isEmpty) return const <DiscoveredObsDevice>[];

    final discovered = <DiscoveredObsDevice>[];

    for (var offset = 0; offset < candidates.length; offset += batchSize) {
      final end = (offset + batchSize) > candidates.length
          ? candidates.length
          : offset + batchSize;
      final batch = candidates.sublist(offset, end);
      final results = await Future.wait(
        batch.map(
          (host) => _probeHost(
            host: host,
            port: port,
            connectTimeout: connectTimeout,
            helloTimeout: helloTimeout,
          ),
        ),
      );
      discovered.addAll(
        results.whereType<DiscoveredObsDevice>(),
      );
    }

    discovered.sort((a, b) => _ipSortKey(a.host).compareTo(_ipSortKey(b.host)));
    return discovered;
  }

  Future<List<String>> _candidateHosts({
    required Iterable<String> preferredHosts,
    required int maxHosts,
  }) async {
    final hosts = <String>{};

    for (final host in preferredHosts) {
      final normalized = host.trim();
      if (_isValidDiscoveryHost(normalized)) {
        hosts.add(normalized);
      }
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (!_isPrivateIpv4(ip)) continue;
          final parts = ip.split('.');
          if (parts.length != 4) continue;
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}.';
          final own = int.tryParse(parts[3]) ?? 0;

          for (var host = 1; host <= 254; host++) {
            if (host == own) continue;
            hosts.add('$prefix$host');
            if (hosts.length >= maxHosts) {
              return hosts.toList(growable: false);
            }
          }
        }
      }
    } catch (_) {
      // Network interface enumeration can fail on some devices/sandboxes.
    }

    hosts.add('10.0.2.2');
    return hosts.take(maxHosts).toList(growable: false);
  }

  Future<DiscoveredObsDevice?> _probeHost({
    required String host,
    required int port,
    required Duration connectTimeout,
    required Duration helloTimeout,
  }) async {
    WebSocket? socket;
    try {
      socket =
          await WebSocket.connect('ws://$host:$port').timeout(connectTimeout);
      final firstFrame = await socket.first.timeout(helloTimeout);
      if (firstFrame is! String) return null;

      final decoded = jsonDecode(firstFrame);
      if (decoded is! Map) return null;

      final op = decoded['op'];
      final data = decoded['d'];
      if (op != 0 || data is! Map) return null;

      final map = data.cast<String, dynamic>();
      final hasObsMarkers =
          map['obsWebSocketVersion'] != null || map['rpcVersion'] != null;
      if (!hasObsMarkers) return null;

      final requiresPassword = map['authentication'] != null;
      final obsVersion = map['obsWebSocketVersion'] as String?;
      return DiscoveredObsDevice(
        host: host,
        port: port,
        requiresPassword: requiresPassword,
        obsVersion: obsVersion,
      );
    } catch (_) {
      return null;
    } finally {
      await socket?.close();
    }
  }

  bool _isPrivateIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  bool _isValidDiscoveryHost(String host) {
    if (host.isEmpty) return false;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    if (address.type != InternetAddressType.IPv4) return false;
    if (address.isLoopback) return false;
    return true;
  }

  String _ipSortKey(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return host;
    final normalized = parts
        .map((part) => int.tryParse(part)?.toString().padLeft(3, '0') ?? part)
        .join('.');
    return normalized;
  }
}
