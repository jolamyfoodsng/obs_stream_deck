import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_review_prompt_service.dart';
import '../test_helpers/test_app_harness.dart';

void main() {
  group('SettingsScreen', () {
    testWidgets('free users see premium upgrade section and review action', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeReview = FakeReviewPromptService();

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/settings',
        reviewPromptService: fakeReview,
      );

      await tester.scrollUntilVisible(
        find.text('DeckPilot Premium'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);
      expect(find.textContaining('Upgrade to Premium'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Rate DeckPilot'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);

      expect(find.text('Rate DeckPilot'), findsOneWidget);

      await tester.tap(find.text('Rate DeckPilot'));
      await pumpAppFrames(tester, const Duration(milliseconds: 400));

      expect(fakeReview.requestReviewCalls, 1);

      await tester.scrollUntilVisible(
        find.text('Contact Support / Send Feedback'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);

      expect(find.text('How to connect to OBS'), findsOneWidget);
      expect(find.text('Contact Support / Send Feedback'), findsOneWidget);
    });

    testWidgets('premium users see activated state', (WidgetTester tester) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
        'premium_unlocked': true,
      });

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/settings',
      );

      await tester.scrollUntilVisible(
        find.text('Activated'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);

      expect(find.text('Activated'), findsOneWidget);
      expect(find.text('Thank you for supporting DeckPilot.'), findsOneWidget);
    });

    testWidgets('support entry opens support dialog', (WidgetTester tester) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/settings',
      );

      await tester.scrollUntilVisible(
        find.text('Contact Support / Send Feedback'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);

      await tester.tap(find.text('Contact Support / Send Feedback'));
      await pumpAppFrames(tester);

      expect(find.text('Contact Support'), findsOneWidget);
      expect(find.text('Copy Note'), findsOneWidget);
    });
  });
}
