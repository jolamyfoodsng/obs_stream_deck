import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/macro_definition.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_macro_repository.dart';
import '../test_helpers/fixtures/sample_data.dart';
import '../test_helpers/test_app_harness.dart';

void main() {
  group('MacroLibraryScreen', () {
    testWidgets('empty state shows the only create action when no macros exist', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/macros',
        macroRepository: FakeMacroRepository(),
      );

      expect(find.text('No macros yet'), findsOneWidget);
      expect(find.text('Create Macro'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(find.text('Create Macro'));
      await pumpAppFrames(tester, const Duration(milliseconds: 500));

      expect(find.text('Macro Editor'), findsOneWidget);
    });

    testWidgets('free user with one macro sees list and locked create fab', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/macros',
        macroRepository: FakeMacroRepository(
          macros: <MacroDefinition>[
            sampleMacro(id: 'macro_1', name: 'Start Service'),
          ],
        ),
      );

      expect(find.text('No macros yet'), findsNothing);
      expect(find.text('Start Service'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Create Macro'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await pumpAppFrames(tester, const Duration(milliseconds: 500));

      expect(find.text('DeckPilot Premium'), findsOneWidget);
    });

    testWidgets('premium user sees list with create fab', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
        'premium_unlocked': true,
      });

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/macros',
        macroRepository: FakeMacroRepository(
          macros: <MacroDefinition>[
            sampleMacro(id: 'macro_1', name: 'Start Service'),
          ],
        ),
      );

      expect(find.text('Start Service'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Create Macro'), findsOneWidget);
    });

    testWidgets('locked macro opens preview sheet before upgrade modal', (
      WidgetTester tester,
    ) async {
      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/macros',
        macroRepository: FakeMacroRepository(
          macros: <MacroDefinition>[
            sampleMacro(id: 'macro_1', name: 'Scene Prep'),
            sampleMacro(id: 'macro_2', name: 'Premium Flow'),
          ],
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Premium Flow'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpAppFrames(tester);
      expect(find.text('Premium Flow'), findsOneWidget);
      expect(find.text('DeckPilot Premium'), findsNothing);

      await tester.tap(find.text('Preview').first);
      await pumpAppFrames(tester, const Duration(milliseconds: 500));

      expect(find.text('Premium Flow'), findsWidgets);
      expect(find.textContaining('ready to run multiple OBS actions'), findsOneWidget);
      expect(find.text('DeckPilot Premium'), findsNothing);
    });
  });
}
