import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/controller_page.dart';
import 'package:obs_stream_deck/features/page_manager/presentation/controllers/page_manager_controller.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_controller_repository.dart';
import '../test_helpers/fixtures/sample_data.dart';
import '../test_helpers/test_container.dart';

void main() {
  group('PageManagerController', () {
    test('free plan blocks creation of a second user page', () async {
      final prefs = await buildTestPreferences();
      final container = createTestContainer(
        sharedPreferences: prefs,
        controllerRepository: FakeControllerRepository(
          pages: <ControllerPage>[
            sampleScenesPage(),
            sampleCustomPage(id: 'emergency', name: 'Emergency'),
          ],
        ),
      );
      addTearDown(container.dispose);

      final controller = container.read(pageManagerControllerProvider.notifier);
      await settleContainer();

      final result = await controller.createPage(name: 'Audio');
      expect(result, isNull);
    });

    test('premium plan can create additional pages', () async {
      final prefs = await buildTestPreferences(<String, Object>{
        'premium_unlocked': true,
      });
      final repository = FakeControllerRepository(
        pages: <ControllerPage>[sampleScenesPage()],
      );
      final container = createTestContainer(
        sharedPreferences: prefs,
        controllerRepository: repository,
      );
      addTearDown(container.dispose);

      final controller = container.read(pageManagerControllerProvider.notifier);
      await settleContainer();

      final result = await controller.createPage(name: 'Audio');
      expect(result, isNotNull);
      expect(repository.pages.length, 2);
      expect(repository.pages.last.name, 'Audio');
    });
  });
}
