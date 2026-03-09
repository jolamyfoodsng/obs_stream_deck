import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:obs_stream_deck/domain/entities/connection_status.dart';
import 'package:obs_stream_deck/domain/entities/controller_page.dart';
import 'package:obs_stream_deck/domain/entities/recording_status.dart';
import 'package:obs_stream_deck/domain/entities/stream_status.dart';

import '../test/test_helpers/fake_shared_preferences.dart';
import '../test/test_helpers/fakes/fake_billing_service.dart';
import '../test/test_helpers/fakes/fake_controller_repository.dart';
import '../test/test_helpers/fakes/fake_obs_repository.dart';
import '../test/test_helpers/fixtures/sample_data.dart';
import '../test/test_helpers/test_app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('DeckPilot integration flows', () {
    testWidgets('first-time user can reach connect flow and load OBS scenes', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences();
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          connectionStatus: ConnectionStatus.disconnected,
          scenes: sampleScenes(count: 4),
          currentScene: null,
        ),
      );
      addTearDown(fakeObs.dispose);

      await tester.pumpWidget(
        buildTestApp(
          sharedPreferences: prefs,
          initialLocation: '/',
          obsRepository: fakeObs,
          controllerRepository: FakeControllerRepository(
            pages: <ControllerPage>[sampleScenesPage()],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await pumpAppFrames(tester, const Duration(milliseconds: 500));

      if (find.text('Skip').evaluate().isNotEmpty) {
        await tester.tap(find.text('Skip').first);
        await pumpAppFrames(tester, const Duration(milliseconds: 400));
      }

      expect(find.text('No OBS scenes loaded'), findsOneWidget);
      await tester.tap(find.text('Connect to OBS'));
      await pumpAppFrames(tester, const Duration(milliseconds: 400));

      await tester.scrollUntilVisible(
        find.text('Manual Setup'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Manual Setup'));
      await pumpAppFrames(tester, const Duration(milliseconds: 400));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '192.168.1.8');
      await tester.enterText(fields.at(1), '4455');
      await tester.enterText(fields.at(2), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
      await pumpAppFrames(tester, const Duration(milliseconds: 700));

      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await pumpAppFrames(tester, const Duration(milliseconds: 1000));

      expect(find.text('Scene 1', skipOffstage: false), findsOneWidget);
      expect(find.text('Scene 4', skipOffstage: false), findsOneWidget);
    });

    testWidgets('real-time OBS changes update quick controls immediately', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          scenes: sampleScenes(count: 3),
          streamStatus: StreamStatus.offline,
          recordingStatus: RecordingStatus.stopped,
        ),
      );
      addTearDown(fakeObs.dispose);

      await tester.pumpWidget(
        buildTestApp(
          sharedPreferences: prefs,
          initialLocation: '/controller',
          obsRepository: fakeObs,
          controllerRepository: FakeControllerRepository(
            pages: <ControllerPage>[sampleScenesPage()],
          ),
        ),
      );
      await pumpAppFrames(tester, const Duration(milliseconds: 500));

      expect(find.text('Start Stream'), findsOneWidget);
      expect(find.text('Start Recording'), findsOneWidget);
      expect(find.text('Mute Mic'), findsOneWidget);

      fakeObs.setStreamStatus(StreamStatus.live);
      fakeObs.setRecordingStatus(RecordingStatus.recording);
      fakeObs.setAudioMuted('mic_main', true);
      fakeObs.setCurrentScene('Scene 2');
      await pumpAppFrames(tester, const Duration(milliseconds: 400));

      expect(find.text('Stop Stream'), findsOneWidget);
      expect(find.text('Stop Recording'), findsOneWidget);
      expect(find.text('Unmute Mic'), findsOneWidget);
      expect(find.text('Scene 2'), findsWidgets);
    });

    testWidgets('free user can preview a premium limit and upgrade', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeBilling = FakeBillingService();

      await tester.pumpWidget(
        buildTestApp(
          sharedPreferences: prefs,
          initialLocation: '/monitor',
          billingService: fakeBilling,
        ),
      );
      await pumpAppFrames(tester, const Duration(milliseconds: 500));

      await tester.tap(find.text('Locked').first);
      await pumpAppFrames(tester, const Duration(milliseconds: 400));
      expect(find.text('DeckPilot Premium'), findsOneWidget);

      await tester.tap(find.text('Upgrade Now'));
      await tester.pump();
      fakeBilling.emitPurchased();
      await pumpAppFrames(tester, const Duration(milliseconds: 700));

      expect(find.text('DeckPilot Premium activated.'), findsOneWidget);
      fakeBilling.dispose();
    });
  });
}
