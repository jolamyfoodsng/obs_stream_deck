import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obs_stream_deck/core/constants/app_constants.dart';
import 'package:obs_stream_deck/core/services/local_storage_service.dart';
import 'package:obs_stream_deck/shared/state/premium_controller.dart';

import '../test_helpers/fakes/fake_billing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('reports clear error when billing is unavailable', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final preferences = await SharedPreferences.getInstance();
    final billing = FakeBillingService(available: false);
    final controller = PremiumController(
      storage: LocalStorageService(preferences),
      billingService: billing,
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.state.billingAvailable, isFalse);
    expect(controller.state.error, contains('Google Play billing is unavailable'));

    final result = await controller.purchasePremium();

    expect(result, PremiumPurchaseResult.unavailable);
    expect(controller.state.error, contains('Google Play billing is unavailable'));

    controller.dispose();
    billing.dispose();
  });

  test('reports missing premium product when store returns no products', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final preferences = await SharedPreferences.getInstance();
    final billing = FakeBillingService(
      available: true,
      returnProduct: false,
    );
    final controller = PremiumController(
      storage: LocalStorageService(preferences),
      billingService: billing,
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.state.billingAvailable, isTrue);
    expect(
      controller.state.error,
      anyOf(
        contains(AppConstants.premiumProductId),
        contains(AppConstants.androidApplicationId),
      ),
    );

    controller.dispose();
    billing.dispose();
  });
}
