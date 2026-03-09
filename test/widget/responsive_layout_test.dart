import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/controller_page.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_controller_repository.dart';
import '../test_helpers/fakes/fake_obs_repository.dart';
import '../test_helpers/fixtures/sample_data.dart';
import '../test_helpers/test_app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Responsive controller layout', () {
    testWidgets('phone width uses compact layout with bottom navigation', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeObs = FakeObsRepository(initialState: sampleObsState());
      addTearDown(fakeObs.dispose);

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/controller',
        obsRepository: fakeObs,
        controllerRepository: FakeControllerRepository(
          pages: <ControllerPage>[sampleScenesPage()],
        ),
      );

      expect(find.text('Control'), findsOneWidget);
      expect(find.text('Pages'), findsOneWidget);
      expect(find.text('Page list hidden. Grid expanded for tablet view.'),
          findsNothing);
    });

    testWidgets('tablet width shows expanded layout with page list', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeObs = FakeObsRepository(initialState: sampleObsState());
      addTearDown(fakeObs.dispose);

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/controller',
        obsRepository: fakeObs,
        controllerRepository: FakeControllerRepository(
          pages: <ControllerPage>[sampleScenesPage(), sampleCustomPage()],
        ),
      );

      expect(find.text('Page list open'), findsOneWidget);
      expect(find.text('Scenes'), findsWidgets);
      expect(find.text('Media'), findsOneWidget);
    });
  });
}
