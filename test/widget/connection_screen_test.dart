import 'package:obs_stream_deck/domain/entities/connection_diagnostic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/connection_status.dart';
import 'package:obs_stream_deck/domain/entities/discovered_obs_device.dart';
import 'package:obs_stream_deck/domain/entities/saved_obs_connection.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_auto_discovery_service.dart';
import '../test_helpers/fakes/fake_connection_diagnostics_service.dart';
import '../test_helpers/fakes/fake_connection_repository.dart';
import '../test_helpers/fakes/fake_obs_repository.dart';
import '../test_helpers/fixtures/sample_data.dart';
import '../test_helpers/test_app_harness.dart';

void main() {
  group('ConnectionScreen', () {
    testWidgets('shows first-time setup guide before first successful connection', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          connectionStatus: ConnectionStatus.disconnected,
        ),
      );
      addTearDown(fakeObs.dispose);

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/connection',
        obsRepository: fakeObs,
      );

      expect(find.text('Before Connecting'), findsOneWidget);
      expect(find.text('REQUIRED'), findsOneWidget);

      await tester.tap(find.text('View Setup Guide'));
      await pumpAppFrames(tester);
      expect(find.text('OBS Setup Guide'), findsOneWidget);
      expect(find.text('Open OBS and click Tools.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close).last);
      await pumpAppFrames(tester);
      expect(find.text('OBS Setup Guide'), findsNothing);
    });

    testWidgets('renders primary connection methods and collapsed help', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/connection',
      );

      expect(find.text('Auto Detect'), findsOneWidget);
      expect(find.text('Wi-Fi'), findsOneWidget);
      expect(find.text('USB'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Find OBS Automatically'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);
      expect(find.text('Find OBS Automatically'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Having trouble connecting?'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);
      expect(find.text('Having trouble connecting?'), findsOneWidget);
      expect(find.textContaining('do not use 127.0.0.1'), findsNothing);
    });

    testWidgets('shows saved connections and connects with manual form', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          connectionStatus: ConnectionStatus.disconnected,
        ),
      );
      final connectionRepository = FakeConnectionRepository(
        savedConnections: <SavedObsConnection>[sampleSavedConnection()],
      );
      addTearDown(fakeObs.dispose);

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/connection',
        obsRepository: fakeObs,
        connectionRepository: connectionRepository,
      );

      await tester.scrollUntilVisible(
        find.text('Studio Mac'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);
      expect(find.text('Studio Mac'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Manual Setup'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Manual Setup'));
      await pumpAppFrames(tester);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), '192.168.1.20');
      await tester.enterText(fields.at(1), '4455');
      await tester.enterText(fields.at(2), 'secret');
      await tester.tap(find.text('Connect'));
      await pumpAppFrames(tester, const Duration(milliseconds: 700));

      expect(fakeObs.connectCalls, 1);
      expect(connectionRepository.config?.host, '192.168.1.20');
    });

    testWidgets('auto detect shows discovered OBS devices', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final autoDiscovery = FakeObsAutoDiscoveryService(
        devices: const <DiscoveredObsDevice>[
          DiscoveredObsDevice(
            host: '192.168.1.8',
            port: 4455,
            requiresPassword: false,
          ),
        ],
      );

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/connection',
        autoDiscoveryService: autoDiscovery,
      );

      await tester.scrollUntilVisible(
        find.text('Find OBS Automatically'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);
      await tester.tap(find.text('Find OBS Automatically'));
      await pumpAppFrames(tester, const Duration(milliseconds: 700));

      expect(autoDiscovery.discoverCalls, 1);
      expect(find.textContaining('OBS Studio (192.168.1.8)'), findsOneWidget);
    });

    testWidgets('shows actionable diagnostics when connection fails', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
        'connection_guide_dismissed': true,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          connectionStatus: ConnectionStatus.disconnected,
        ),
      )
        ..connectFailureStatus = ConnectionStatus.notFound
        ..connectFailureMessage = 'Timed out reaching OBS.';
      final diagnostics = FakeConnectionDiagnosticsService(
        failureDiagnostics: const <ConnectionDiagnostic>[
          ConnectionDiagnostic(
            type: ConnectionDiagnosticType.firewallBlocked,
            severity: ConnectionDiagnosticSeverity.error,
            title: 'Connection blocked by firewall',
            message: 'DeckPilot could not open a socket to OBS.',
            fix: 'Allow OBS through your firewall and retry.',
          ),
        ],
      );
      addTearDown(fakeObs.dispose);

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/connection',
        obsRepository: fakeObs,
        diagnosticsService: diagnostics,
      );

      await tester.scrollUntilVisible(
        find.text('Manual Setup'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Manual Setup'));
      await pumpAppFrames(tester);
      await tester.enterText(find.byType(TextField).first, '192.168.1.50');
      await pumpAppFrames(tester);
      await tester.tap(find.text('Connect'));
      await pumpAppFrames(tester, const Duration(milliseconds: 700));

      expect(find.text('Connection Diagnostics'), findsOneWidget);
      expect(find.text('Connection blocked by firewall'), findsOneWidget);
      expect(find.text('Allow OBS through your firewall and retry.'), findsOneWidget);
    });

    testWidgets('manual setup explains background reconnect state', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          connectionStatus: ConnectionStatus.reconnecting,
        ),
      );
      addTearDown(fakeObs.dispose);

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/connection',
        obsRepository: fakeObs,
      );

      await tester.scrollUntilVisible(
        find.text('Manual Setup'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Manual Setup'));
      await pumpAppFrames(tester);

      expect(find.text('Background reconnect in progress'), findsOneWidget);
      expect(
        find.textContaining('retrying your saved OBS connection'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
