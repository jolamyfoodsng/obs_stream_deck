import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/controller_page.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_controller_repository.dart';
import '../test_helpers/fixtures/sample_data.dart';
import '../test_helpers/test_app_harness.dart';

void main() {
  group('PageManagerScreen', () {
    testWidgets('shows locked premium page slots without immediate paywall', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/page-manager',
        controllerRepository: FakeControllerRepository(
          pages: <ControllerPage>[sampleScenesPage()],
        ),
      );

      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('DeckPilot Premium'), findsNothing);

      await tester.tap(find.text('Page 2'));
      await pumpAppFrames(tester, const Duration(milliseconds: 500));

      expect(find.text('More Deck Pages'), findsOneWidget);
      expect(find.text('DeckPilot Premium'), findsNothing);
    });

    testWidgets('free plan shows page limit dialog when creating second page', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/page-manager',
        controllerRepository: FakeControllerRepository(
          pages: <ControllerPage>[sampleScenesPage()],
        ),
      );

      await tester.tap(find.text('Add New Page'));
      await pumpAppFrames(tester, const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField).last, 'Audio');
      await tester.tap(find.text('Create Page'));
      await pumpAppFrames(tester, const Duration(milliseconds: 500));

      expect(find.text('Page limit reached'), findsOneWidget);
      expect(find.textContaining('Free users can create only 1 deck page'), findsOneWidget);
    });
  });
}
