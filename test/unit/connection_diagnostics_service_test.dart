import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/core/services/connection_diagnostics_service.dart';
import 'package:obs_stream_deck/domain/entities/connection_diagnostic.dart';
import 'package:obs_stream_deck/domain/entities/connection_method.dart';
import 'package:obs_stream_deck/domain/entities/connection_preflight_report.dart';
import 'package:obs_stream_deck/domain/entities/connection_status.dart';

void main() {
  group('ConnectionDiagnosticsService', () {
    const service = ConnectionDiagnosticsService();

    test('flags loopback host as invalid for Wi-Fi connections', () {
      const report = ConnectionPreflightReport(
        localAddresses: <String>['192.168.1.10'],
        hasLocalNetwork: true,
        hostIsLoopback: true,
        hostIsPrivateIpv4: false,
        likelySameSubnet: false,
        hostResolved: true,
        tcpReachable: false,
        portOpen: false,
      );

      final diagnostics = service.buildPreflightDiagnostics(
        report: report,
        host: '127.0.0.1',
        port: 4455,
        method: ConnectionMethod.wifi,
      );

      expect(
        diagnostics.any(
          (item) => item.type == ConnectionDiagnosticType.invalidHost,
        ),
        isTrue,
      );
    });

    test('maps wrong password failures to auth diagnostic', () {
      const report = ConnectionPreflightReport(
        localAddresses: <String>['192.168.1.10'],
        hasLocalNetwork: true,
        hostIsLoopback: false,
        hostIsPrivateIpv4: true,
        likelySameSubnet: true,
        hostResolved: true,
        tcpReachable: true,
        portOpen: true,
      );

      final diagnostics = service.buildFailureDiagnostics(
        status: ConnectionStatus.wrongPassword,
        host: '192.168.1.8',
        port: 4455,
        method: ConnectionMethod.wifi,
        report: report,
        rawMessage: 'OBS authentication failed.',
      );

      expect(diagnostics.first.type, ConnectionDiagnosticType.wrongPassword);
      expect(diagnostics.first.title, 'Authentication failed');
    });

    test('maps closed port failures to websocket disabled guidance', () {
      const report = ConnectionPreflightReport(
        localAddresses: <String>['192.168.1.10'],
        hasLocalNetwork: true,
        hostIsLoopback: false,
        hostIsPrivateIpv4: true,
        likelySameSubnet: true,
        hostResolved: true,
        tcpReachable: true,
        portOpen: false,
        tcpFailure: 'Connection refused',
      );

      final diagnostics = service.buildFailureDiagnostics(
        status: ConnectionStatus.notFound,
        host: '192.168.1.8',
        port: 4455,
        method: ConnectionMethod.wifi,
        report: report,
        rawMessage: 'OBS WebSocket is not responding on this host/port.',
      );

      expect(diagnostics.first.type, ConnectionDiagnosticType.websocketDisabled);
      expect(diagnostics.first.fix, contains('WebSocket Server'));
    });
  });
}
