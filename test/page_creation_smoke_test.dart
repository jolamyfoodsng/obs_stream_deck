import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obs_stream_deck/app/app.dart';
import 'package:obs_stream_deck/shared/state/app_providers.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const ObsStreamDeckApp(),
      ),
    );

    // Initial route is branded splash. Advance time to land on controller.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  }

  testWidgets('can create a page from controller without framework assert',
      (tester) async {
    await pumpApp(tester);

    final addPageButton = find.byIcon(Icons.add_box_outlined);
    if (addPageButton.evaluate().isNotEmpty) {
      await tester.tap(addPageButton);
      await tester.pumpAndSettle();
    } else {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Page'));
      await tester.pumpAndSettle();
    }

    await tester.enterText(find.byType(TextField), 'Controller Test Page');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Page'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('can create a page from page manager without framework assert',
      (tester) async {
    await pumpApp(tester);

    // Navigate to Page Manager via bottom navigation.
    await tester.tap(find.text('Pages'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add New Page'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Test Page');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Page'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
