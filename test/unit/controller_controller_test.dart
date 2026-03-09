import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/button_action.dart';
import 'package:obs_stream_deck/domain/entities/controller_button.dart';
import 'package:obs_stream_deck/domain/entities/controller_page.dart';
import 'package:obs_stream_deck/domain/entities/stream_status.dart';
import 'package:obs_stream_deck/features/controller/presentation/controllers/controller_controller.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_controller_repository.dart';
import '../test_helpers/fakes/fake_obs_repository.dart';
import '../test_helpers/fixtures/sample_data.dart';
import '../test_helpers/test_container.dart';

void main() {
  group('ControllerController', () {
    test('syncs scenes page from OBS and shows locked placeholder for free plan',
        () async {
      final prefs = await buildTestPreferences();
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(scenes: sampleScenes(count: 8)),
      );
      final controllerRepository = FakeControllerRepository(
        pages: <ControllerPage>[sampleScenesPage()],
      );
      final container = createTestContainer(
        sharedPreferences: prefs,
        obsRepository: fakeObs,
        controllerRepository: controllerRepository,
      );
      addTearDown(() {
        fakeObs.dispose();
        container.dispose();
      });

      final controller = container.read(controllerControllerProvider.notifier);
      await settleContainer();
      await controller.refreshPages();
      await settleContainer();

      final state = container.read(controllerControllerProvider);
      final scenesPage = state.pages.firstWhere((page) => page.id == 'scenes');
      expect(scenesPage.buttons.length, 7);
      expect(scenesPage.buttons.last.label, 'Unlock More Scenes');
      expect(scenesPage.buttons.last.action.metadata['premiumFeature'], 'unlimitedScenes');
    });

    test('start and stop stream buttons reflect live OBS state', () async {
      final prefs = await buildTestPreferences();
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(streamStatus: StreamStatus.offline),
      );
      final container = createTestContainer(
        sharedPreferences: prefs,
        obsRepository: fakeObs,
        controllerRepository: FakeControllerRepository(
          pages: <ControllerPage>[sampleScenesPage()],
        ),
      );
      addTearDown(() {
        fakeObs.dispose();
        container.dispose();
      });

      final controller = container.read(controllerControllerProvider.notifier);
      await settleContainer();

      const startButton = ControllerButton(
        id: 'start_stream',
        label: 'Start Stream',
        icon: 'play_arrow',
        category: DeckButtonCategory.stream,
        action: ButtonAction(type: ButtonActionType.startStream),
        position: 0,
      );
      const stopButton = ControllerButton(
        id: 'stop_stream',
        label: 'Stop Stream',
        icon: 'stop',
        category: DeckButtonCategory.stream,
        action: ButtonAction(type: ButtonActionType.stopStream),
        position: 1,
      );

      expect(controller.resolveButtonState(startButton).enabled, isTrue);
      expect(controller.resolveButtonState(stopButton).enabled, isFalse);

      fakeObs.setStreamStatus(StreamStatus.live);
      await settleContainer();

      expect(controller.resolveButtonState(startButton).enabled, isFalse);
      expect(controller.resolveButtonState(stopButton).enabled, isTrue);
      expect(controller.resolveButtonState(stopButton).active, isTrue);
    });

    test('external scene changes update active button state', () async {
      final prefs = await buildTestPreferences();
      final scenes = sampleScenes(count: 3);
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(scenes: scenes, currentScene: 'Scene 1'),
      );
      final controllerRepository = FakeControllerRepository(
        pages: <ControllerPage>[sampleScenesPage()],
      );
      final container = createTestContainer(
        sharedPreferences: prefs,
        obsRepository: fakeObs,
        controllerRepository: controllerRepository,
      );
      addTearDown(() {
        fakeObs.dispose();
        container.dispose();
      });

      final controller = container.read(controllerControllerProvider.notifier);
      await settleContainer();
      await controller.refreshPages();
      await settleContainer();

      var state = container.read(controllerControllerProvider);
      var scenesPage = state.pages.firstWhere((page) => page.id == 'scenes');
      expect(scenesPage.buttons.first.label, 'Scene 1');
      expect(
        controller.isButtonActive(
              scenesPage.buttons.first,
            ),
        isTrue,
      );

      fakeObs.setCurrentScene('Scene 2');
      await settleContainer();

      state = container.read(controllerControllerProvider);
      scenesPage = state.pages.firstWhere((page) => page.id == 'scenes');
      expect(
        controller.isButtonActive(
              scenesPage.buttons[1],
            ),
        isTrue,
      );
      expect(
        controller.isButtonActive(
              scenesPage.buttons.first,
            ),
        isFalse,
      );
    });

    test('premium users receive stream health warnings when congestion rises',
        () async {
      final prefs = await buildTestPreferences(<String, Object>{
        'premium_unlocked': true,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          streamStatus: StreamStatus.live,
          outputCongestion: 0.20,
        ),
      );
      final container = createTestContainer(
        sharedPreferences: prefs,
        obsRepository: fakeObs,
        controllerRepository: FakeControllerRepository(
          pages: <ControllerPage>[sampleScenesPage()],
        ),
      );
      addTearDown(() {
        fakeObs.dispose();
        container.dispose();
      });

      container.read(controllerControllerProvider.notifier);
      await settleContainer();

      final banner = container.read(controllerControllerProvider).banner;
      expect(banner?.key, 'stream_congestion');
      expect(banner?.message, contains('High congestion detected'));
    });

    test('long press protected button returns hold required on tap', () async {
      final prefs = await buildTestPreferences();
      final fakeObs = FakeObsRepository();
      final container = createTestContainer(
        sharedPreferences: prefs,
        obsRepository: fakeObs,
        controllerRepository: FakeControllerRepository(
          pages: <ControllerPage>[sampleScenesPage()],
        ),
      );
      addTearDown(() {
        fakeObs.dispose();
        container.dispose();
      });

      final controller = container.read(controllerControllerProvider.notifier);
      await settleContainer();

      final muteButton = sampleMuteMicButton(longPressTrigger: true);
      final outcome = await controller.onButtonTap(muteButton);
      expect(outcome, ControllerButtonInteractionOutcome.holdRequired);
    });
  });
}
