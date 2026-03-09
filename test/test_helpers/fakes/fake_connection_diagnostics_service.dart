import 'package:obs_stream_deck/core/services/connection_diagnostics_service.dart';
import 'package:obs_stream_deck/domain/entities/connection_diagnostic.dart';
import 'package:obs_stream_deck/domain/entities/connection_method.dart';
import 'package:obs_stream_deck/domain/entities/connection_preflight_report.dart';
import 'package:obs_stream_deck/domain/entities/connection_status.dart';

class FakeConnectionDiagnosticsService extends ConnectionDiagnosticsService {
  FakeConnectionDiagnosticsService({
    ConnectionPreflightReport? preflight,
    List<ConnectionDiagnostic>? preflightDiagnostics,
    List<ConnectionDiagnostic>? failureDiagnostics,
  })  : _preflight = preflight,
        _preflightDiagnostics = preflightDiagnostics,
        _failureDiagnostics = failureDiagnostics;

  final ConnectionPreflightReport? _preflight;
  final List<ConnectionDiagnostic>? _preflightDiagnostics;
  final List<ConnectionDiagnostic>? _failureDiagnostics;

  int preflightCalls = 0;
  int failureCalls = 0;

  @override
  Future<ConnectionPreflightReport> runPreflight({
    required String host,
    required int port,
    required ConnectionMethod method,
  }) async {
    preflightCalls += 1;
    return _preflight ??
        const ConnectionPreflightReport(
          localAddresses: <String>['192.168.1.10'],
          hasLocalNetwork: true,
          hostIsLoopback: false,
          hostIsPrivateIpv4: true,
          likelySameSubnet: true,
          hostResolved: true,
          tcpReachable: true,
          portOpen: true,
        );
  }

  @override
  List<ConnectionDiagnostic> buildPreflightDiagnostics({
    required ConnectionPreflightReport report,
    required String host,
    required int port,
    required ConnectionMethod method,
  }) {
    return _preflightDiagnostics ?? const <ConnectionDiagnostic>[];
  }

  @override
  List<ConnectionDiagnostic> buildFailureDiagnostics({
    required ConnectionStatus status,
    required String host,
    required int port,
    required ConnectionMethod method,
    required ConnectionPreflightReport report,
    String? rawMessage,
  }) {
    failureCalls += 1;
    return _failureDiagnostics ??
        const <ConnectionDiagnostic>[
          ConnectionDiagnostic(
            type: ConnectionDiagnosticType.unknown,
            severity: ConnectionDiagnosticSeverity.error,
            title: 'Connection failed',
            message: 'Fake diagnostics failure.',
            fix: 'Check fake settings.',
          ),
        ];
  }
}
