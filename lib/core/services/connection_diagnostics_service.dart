import 'dart:async';
import 'dart:io';

import '../../domain/entities/connection_diagnostic.dart';
import '../../domain/entities/connection_method.dart';
import '../../domain/entities/connection_preflight_report.dart';
import '../../domain/entities/connection_status.dart';

class ConnectionDiagnosticsService {
  const ConnectionDiagnosticsService();

  Future<ConnectionPreflightReport> runPreflight({
    required String host,
    required int port,
    required ConnectionMethod method,
  }) async {
    final trimmedHost = host.trim();
    final localAddresses = await _localAddresses();
    final hostAddress = InternetAddress.tryParse(trimmedHost);
    final hostResolved =
        hostAddress != null || await _canResolveHost(trimmedHost);
    final hostIsLoopback =
        hostAddress?.isLoopback == true || trimmedHost == 'localhost';
    final hostIsPrivateIpv4 =
        hostAddress != null && _isPrivateIpv4(trimmedHost);
    final likelySameSubnet = hostIsPrivateIpv4 &&
        localAddresses.any((local) => _sharesSubnet(local, trimmedHost));

    var tcpReachable = false;
    var portOpen = false;
    String? tcpFailure;

    if (trimmedHost.isNotEmpty) {
      try {
        final socket = await Socket.connect(
          trimmedHost,
          port,
          timeout: const Duration(seconds: 2),
        );
        tcpReachable = true;
        portOpen = true;
        socket.destroy();
      } on SocketException catch (error) {
        tcpFailure = error.message;
        final lower = error.message.toLowerCase();
        final refused = lower.contains('refused');
        tcpReachable = refused;
        portOpen = false;
      } on TimeoutException {
        tcpFailure = 'Timed out';
        tcpReachable = false;
        portOpen = false;
      } catch (error) {
        tcpFailure = error.toString();
      }
    }

    return ConnectionPreflightReport(
      localAddresses: localAddresses,
      hasLocalNetwork:
          localAddresses.isNotEmpty || method == ConnectionMethod.usb,
      hostIsLoopback: hostIsLoopback,
      hostIsPrivateIpv4: hostIsPrivateIpv4,
      likelySameSubnet: likelySameSubnet,
      hostResolved: hostResolved,
      tcpReachable: tcpReachable,
      portOpen: portOpen,
      tcpFailure: tcpFailure,
    );
  }

  List<ConnectionDiagnostic> buildPreflightDiagnostics({
    required ConnectionPreflightReport report,
    required String host,
    required int port,
    required ConnectionMethod method,
  }) {
    final diagnostics = <ConnectionDiagnostic>[];
    final trimmedHost = host.trim();

    if (method == ConnectionMethod.usb) {
      diagnostics.add(
        const ConnectionDiagnostic(
          type: ConnectionDiagnosticType.usbGuidance,
          severity: ConnectionDiagnosticSeverity.info,
          title: 'USB mode requires a local tunnel',
          message:
              'Use USB Mode if Wi-Fi is unavailable. This app expects ADB reverse or a USB network interface to expose OBS locally.',
          fix:
              'On your computer run adb reverse tcp:4455 tcp:4455, then keep Host as 127.0.0.1.',
        ),
      );
      return diagnostics;
    }

    if (!report.hasLocalNetwork) {
      diagnostics.add(
        const ConnectionDiagnostic(
          type: ConnectionDiagnosticType.networkUnavailable,
          severity: ConnectionDiagnosticSeverity.warning,
          title: 'No local network detected',
          message:
              'This device does not appear to be on a Wi-Fi or hotspot network right now.',
          fix:
              'Connect both devices to the same Wi-Fi or hotspot, then try again.',
        ),
      );
    }

    if (report.hostIsLoopback) {
      diagnostics.add(
        const ConnectionDiagnostic(
          type: ConnectionDiagnosticType.invalidHost,
          severity: ConnectionDiagnosticSeverity.warning,
          title: 'Loopback address detected',
          message:
              '127.0.0.1 on your phone points back to the phone itself, not to the OBS computer.',
          fix:
              'Enter the local IP address of the computer running OBS instead.',
        ),
      );
    }

    if (report.hostIsPrivateIpv4 && !report.likelySameSubnet) {
      diagnostics.add(
        ConnectionDiagnostic(
          type: ConnectionDiagnosticType.differentNetwork,
          severity: ConnectionDiagnosticSeverity.warning,
          title: 'Devices may be on different networks',
          message:
              '$trimmedHost does not appear to be on the same local subnet as this device.',
          fix:
              'Put your phone and OBS computer on the same Wi-Fi or hotspot network, then retry.',
        ),
      );
    }

    if (trimmedHost.isNotEmpty && !report.hostResolved) {
      diagnostics.add(
        ConnectionDiagnostic(
          type: ConnectionDiagnosticType.invalidHost,
          severity: ConnectionDiagnosticSeverity.error,
          title: 'Host could not be resolved',
          message: 'The host "$trimmedHost" could not be found on the network.',
          fix: 'Check the host/IP and try again.',
        ),
      );
    }

    if (trimmedHost.isNotEmpty &&
        !report.portOpen &&
        report.tcpFailure != null) {
      diagnostics.add(
        ConnectionDiagnostic(
          type: ConnectionDiagnosticType.networkCheck,
          severity: ConnectionDiagnosticSeverity.info,
          title: 'Network probe result',
          message: 'No TCP response from $trimmedHost:$port yet.',
          fix:
              'If OBS is open, verify the WebSocket port and allow OBS through your firewall.',
        ),
      );
    }

    return diagnostics;
  }

  List<ConnectionDiagnostic> buildFailureDiagnostics({
    required ConnectionStatus status,
    required String host,
    required int port,
    required ConnectionMethod method,
    required ConnectionPreflightReport report,
    String? rawMessage,
  }) {
    final diagnostics = <ConnectionDiagnostic>[];
    final message = (rawMessage ?? '').trim();
    final lower = message.toLowerCase();

    if (status == ConnectionStatus.wrongPassword ||
        lower.contains('authentication') ||
        lower.contains('4005')) {
      diagnostics.add(
        const ConnectionDiagnostic(
          type: ConnectionDiagnosticType.wrongPassword,
          severity: ConnectionDiagnosticSeverity.error,
          title: 'Authentication failed',
          message: 'The OBS WebSocket password was rejected.',
          fix:
              'Open OBS → Tools → WebSocket Server Settings and verify the password, or open the setup guide in DeckPilot.',
        ),
      );
      return diagnostics;
    }

    if (method != ConnectionMethod.usb && report.hostIsLoopback) {
      diagnostics.add(
        const ConnectionDiagnostic(
          type: ConnectionDiagnosticType.invalidHost,
          severity: ConnectionDiagnosticSeverity.error,
          title: 'Wrong host for a phone connection',
          message:
              '127.0.0.1 or localhost only works on the same device running OBS.',
          fix:
              'Use the local IP address of your OBS computer, or switch to USB Mode.',
        ),
      );
    }

    if (!report.hasLocalNetwork && method != ConnectionMethod.usb) {
      diagnostics.add(
        const ConnectionDiagnostic(
          type: ConnectionDiagnosticType.networkUnavailable,
          severity: ConnectionDiagnosticSeverity.error,
          title: 'No shared network detected',
          message:
              'This device is not currently on a Wi-Fi or hotspot network that OBS can use.',
          fix:
              'Connect both devices to the same Wi-Fi or hotspot network, then try again.',
        ),
      );
    }

    if (report.hostIsPrivateIpv4 &&
        !report.likelySameSubnet &&
        method != ConnectionMethod.usb) {
      diagnostics.add(
        const ConnectionDiagnostic(
          type: ConnectionDiagnosticType.differentNetwork,
          severity: ConnectionDiagnosticSeverity.error,
          title: 'Different network detected',
          message:
              'Your phone and OBS computer do not appear to be on the same local network.',
          fix: 'Join the same Wi-Fi/hotspot network on both devices and retry.',
        ),
      );
    }

    if (!report.hostResolved) {
      diagnostics.add(
        ConnectionDiagnostic(
          type: ConnectionDiagnosticType.invalidHost,
          severity: ConnectionDiagnosticSeverity.error,
          title: 'Host could not be found',
          message: 'The host "$host" could not be resolved.',
          fix: 'Check the IP/host and try again.',
        ),
      );
    }

    if (!report.portOpen) {
      final lowerFailure = (report.tcpFailure ?? '').toLowerCase();
      if (lowerFailure.contains('refused')) {
        diagnostics.add(
          ConnectionDiagnostic(
            type: ConnectionDiagnosticType.websocketDisabled,
            severity: ConnectionDiagnosticSeverity.error,
            title: 'OBS WebSocket is not responding',
            message:
                'Nothing accepted a connection on $host:$port. OBS may be closed, WebSocket may be disabled, or the port may be wrong.',
            fix:
                'Open OBS → Tools → WebSocket Server Settings, enable WebSocket Server, confirm the port is $port, or open the setup guide in DeckPilot.',
          ),
        );
      } else if ((report.tcpFailure ?? '').isNotEmpty) {
        diagnostics.add(
          ConnectionDiagnostic(
            type: ConnectionDiagnosticType.firewallBlocked,
            severity: ConnectionDiagnosticSeverity.error,
            title: 'Connection blocked before OBS responded',
            message:
                'The app could not open a socket to $host:$port. This often means a firewall, client isolation, or a network mismatch.',
            fix:
                'Allow OBS through your firewall/router and make sure both devices can reach each other locally.',
          ),
        );
      }
    }

    if (lower.contains('handshake') ||
        lower.contains('hello') ||
        lower.contains('rpc') ||
        lower.contains('protocol')) {
      diagnostics.add(
        const ConnectionDiagnostic(
          type: ConnectionDiagnosticType.versionMismatch,
          severity: ConnectionDiagnosticSeverity.error,
          title: 'OBS WebSocket version mismatch',
          message:
              'OBS did not answer with the expected obs-websocket v5 protocol.',
          fix:
              'Use OBS 28+ with the built-in WebSocket server, or verify you are connecting to the correct port.',
        ),
      );
    }

    if (diagnostics.isEmpty) {
      diagnostics.add(
        const ConnectionDiagnostic(
          type: ConnectionDiagnosticType.unknown,
          severity: ConnectionDiagnosticSeverity.error,
          title: 'Connection failed',
          message:
              'DeckPilot could not finish the OBS connection with the current settings.',
          fix:
              'Try Find OBS Automatically first, then QR scan, then Manual Setup. If OBS is open, verify WebSocket Server is enabled or open the setup guide in DeckPilot.',
        ),
      );
    }

    return diagnostics;
  }

  Future<List<String>> _localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      return interfaces
          .expand((interface) => interface.addresses)
          .map((address) => address.address)
          .where(_isPrivateIpv4)
          .toSet()
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<bool> _canResolveHost(String host) async {
    if (host.isEmpty) return false;
    try {
      final addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 2));
      return addresses.isNotEmpty;
    } catch (_) {
      return false;
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

  bool _sharesSubnet(String a, String b) {
    final aParts = a.split('.');
    final bParts = b.split('.');
    if (aParts.length != 4 || bParts.length != 4) return false;
    return aParts[0] == bParts[0] &&
        aParts[1] == bParts[1] &&
        aParts[2] == bParts[2];
  }
}
