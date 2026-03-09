import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/button_action.dart';
import 'package:obs_stream_deck/domain/entities/connection_status.dart';
import 'package:obs_stream_deck/domain/entities/controller_button.dart';
import 'package:obs_stream_deck/domain/entities/controller_page.dart';
import 'package:obs_stream_deck/domain/entities/scene_item.dart';
import 'package:obs_stream_deck/domain/entities/stream_status.dart';
import 'package:obs_stream_deck/domain/entities/recording_status.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_controller_repository.dart';
import '../test_helpers/fakes/fake_obs_repository.dart';
import '../test_helpers/fixtures/sample_data.dart';
import '../test_helpers/test_app_harness.dart';

void main() {
  group('ControllerScreen', () {
    testWidgets('shows disconnected empty state and no dummy scenes', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          connectionStatus: ConnectionStatus.disconnected,
          scenes: const <SceneItem>[],
          currentScene: null,
        ),
      );
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

      expect(find.text('No OBS scenes loaded'), findsOneWidget);
      expect(
        find.text('Connect to OBS to load your real scenes, audio inputs, and controls.'),
        findsOneWidget,
      );
      expect(find.text('Intro'), findsNothing);
      expect(find.text('Gaming'), findsNothing);
    });

    testWidgets('renders real OBS scenes and locked scene placeholder for free users', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(scenes: sampleScenes(count: 8)),
      );
      addTearDown(fakeObs.dispose);
      final sceneButtons = List<ControllerButton>.generate(
        6,
        (index) => sampleSceneButton(
          id: 'btn_scene_$index',
          label: 'Scene ${index + 1}',
          targetId: 'scene_$index',
          position: index,
        ),
      )..add(
          const ControllerButton(
            id: 'premium_unlock_scenes',
            label: 'Unlock More Scenes',
            icon: 'lock',
            category: DeckButtonCategory.utility,
            action: ButtonAction(
              type: ButtonActionType.runMacro,
              metadata: <String, dynamic>{
                'premiumFeature': 'unlimitedScenes',
              },
            ),
            position: 6,
          ),
        );

      await pumpTestApp(
        tester,
        sharedPreferences: prefs,
        initialLocation: '/controller',
        obsRepository: fakeObs,
        controllerRepository: FakeControllerRepository(
          pages: <ControllerPage>[
            sampleScenesPage(buttons: sceneButtons),
          ],
        ),
      );
      await pumpAppFrames(tester, const Duration(milliseconds: 400));

      expect(find.text('Scene 1', skipOffstage: false), findsOneWidget);
      expect(find.text('Scene 6', skipOffstage: false), findsOneWidget);
      expect(find.text('Unlock More Scenes'), findsOneWidget);
      expect(find.text('Scene 7'), findsNothing);
    });

    testWidgets('quick controls update when OBS state changes externally', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await buildTestPreferences(<String, Object>{
        'tutorial_completed': true,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          streamStatus: StreamStatus.offline,
          recordingStatus: RecordingStatus.stopped,
        ),
      );
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
      await pumpAppFrames(tester, const Duration(milliseconds: 600));

      expect(find.text('Start Stream'), findsOneWidget);
      expect(find.text('Start Recording'), findsOneWidget);
      expect(find.text('Mute Mic'), findsOneWidget);

      fakeObs.setStreamStatus(StreamStatus.live);
      fakeObs.setRecordingStatus(RecordingStatus.recording);
      fakeObs.setAudioMuted('mic_main', true);
      await pumpAppFrames(tester, const Duration(milliseconds: 400));

      expect(find.text('Stop Stream'), findsOneWidget);
      expect(find.text('Stop Recording'), findsOneWidget);
      expect(find.text('Unmute Mic'), findsOneWidget);
    });
  });
}
