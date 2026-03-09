import 'package:flutter_test/flutter_test.dart';
import 'package:obs_stream_deck/domain/entities/connection_status.dart';
import 'package:obs_stream_deck/core/constants/storage_keys.dart';
import 'package:obs_stream_deck/core/services/local_storage_service.dart';
import 'package:obs_stream_deck/shared/state/app_engagement_controller.dart';

import '../test_helpers/fake_shared_preferences.dart';
import '../test_helpers/fakes/fake_obs_repository.dart';
import '../test_helpers/fakes/fake_review_prompt_service.dart';
import '../test_helpers/fixtures/sample_data.dart';

void main() {
  group('AppEngagementController', () {
    test('automatic review waits until thresholds are met', () async {
      final prefs = await buildTestPreferences(<String, Object>{
        StorageKeys.installTimestamp:
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        StorageKeys.appOpenCount: 5,
        StorageKeys.successfulObsConnections: 3,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          connectionStatus: ConnectionStatus.disconnected,
        ),
      );
      final fakeReview = FakeReviewPromptService();
      final controller = AppEngagementController(
        localStorage: LocalStorageService(prefs),
        obsRepository: fakeObs,
        reviewPromptService: fakeReview,
      );
      addTearDown(() {
        controller.dispose();
        fakeObs.dispose();
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final didRequest = await controller.maybeRequestReviewIfEligible(
        runtimeState: sampleObsState(),
      );

      expect(didRequest, isFalse);
      expect(fakeReview.requestReviewCalls, 0);
    });

    test('first app open marks tutorial as pending once', () async {
      final prefs = await buildTestPreferences();
      final fakeObs = FakeObsRepository(initialState: sampleObsState());
      final controller = AppEngagementController(
        localStorage: LocalStorageService(prefs),
        obsRepository: fakeObs,
        reviewPromptService: FakeReviewPromptService(),
      );
      addTearDown(() {
        controller.dispose();
        fakeObs.dispose();
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await controller.recordAppOpen();

      expect(controller.state.appOpenCount, 1);
      expect(controller.state.tutorialPending, isTrue);

      await controller.consumeTutorialPending();
      expect(controller.state.tutorialPending, isFalse);
    });

    test('eligible successful usage triggers native review request', () async {
      final prefs = await buildTestPreferences(<String, Object>{
        StorageKeys.installTimestamp:
            DateTime.now().subtract(const Duration(days: 5)).toIso8601String(),
        StorageKeys.appOpenCount: 5,
        StorageKeys.successfulObsConnections: 3,
      });
      final fakeObs = FakeObsRepository(
        initialState: sampleObsState(
          connectionStatus: ConnectionStatus.disconnected,
        ),
      );
      final fakeReview = FakeReviewPromptService();
      final controller = AppEngagementController(
        localStorage: LocalStorageService(prefs),
        obsRepository: fakeObs,
        reviewPromptService: fakeReview,
      );
      addTearDown(() {
        controller.dispose();
        fakeObs.dispose();
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final didRequest = await controller.maybeRequestReviewIfEligible(
        runtimeState: sampleObsState(),
      );

      expect(didRequest, isTrue);
      expect(fakeReview.requestReviewCalls, 1);
    });

    test('manual review falls back to store listing when native review unavailable',
        () async {
      final prefs = await buildTestPreferences();
      final fakeObs = FakeObsRepository(initialState: sampleObsState());
      final fakeReview = FakeReviewPromptService(available: false);
      final controller = AppEngagementController(
        localStorage: LocalStorageService(prefs),
        obsRepository: fakeObs,
        reviewPromptService: fakeReview,
      );
      addTearDown(() {
        controller.dispose();
        fakeObs.dispose();
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final didRequest = await controller.requestManualReview();

      expect(didRequest, isTrue);
      expect(fakeReview.openStoreListingCalls, 1);
    });
  });
}
