import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/stream_status.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_obs_repository.dart';
import '../test_helpers/fixtures/sample_data.dart';
import '../test_helpers/test_app_harness.dart';

void main() {
  group('DashboardScreen', () {
    testWidgets('free users can open monitor page before hitting premium modal', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeObs = FakeObsRepository(initialState: sampleObsState());
      addTearDown(fakeObs.dispose);

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/monitor',
        obsRepository: fakeObs,
      );

      expect(find.text('Monitor stream health in real time.'), findsOneWidget);
      expect(find.text('DeckPilot Premium'), findsNothing);
      expect(find.text('Advanced Stream Health'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('BITRATE'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);
      await tester.tap(find.text('BITRATE'));
      await pumpAppFrames(tester, const Duration(milliseconds: 500));

      expect(find.text('DeckPilot Premium'), findsOneWidget);
    });

    testWidgets('premium users see live advanced metrics', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
        'premium_unlocked': true,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          streamStatus: StreamStatus.live,
          bitrateKbps: 5200,
          cpuUsagePercent: 21.5,
        ),
      );
      addTearDown(fakeObs.dispose);

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/monitor',
        obsRepository: fakeObs,
      );

      await tester.scrollUntilVisible(
        find.text('5200 kbps'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);
      expect(find.text('5200 kbps'), findsOneWidget);
      expect(find.text('21.5%'), findsOneWidget);
      expect(find.text('Locked'), findsNothing);
    });
  });
}
