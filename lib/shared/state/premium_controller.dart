import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/premium_billing_service.dart';
import '../../domain/entities/premium_feature.dart';

enum PremiumPurchaseResult {
  success,
  alreadyPremium,
  unavailable,
  cancelled,
  failed,
}

class PremiumState {
  const PremiumState({
    required this.isPremium,
    required this.billingAvailable,
    required this.isLoading,
    required this.purchasePending,
    required this.productPrice,
    required this.ready,
    this.error,
  });

  final bool isPremium;
  final bool billingAvailable;
  final bool isLoading;
  final bool purchasePending;
  final String productPrice;
  final bool ready;
  final String? error;

  bool isUnlocked(PremiumFeature feature) {
    return isPremium;
  }

  PremiumState copyWith({
    bool? isPremium,
    bool? billingAvailable,
    bool? isLoading,
    bool? purchasePending,
    String? productPrice,
    bool? ready,
    String? error,
    bool clearError = false,
  }) {
    return PremiumState(
      isPremium: isPremium ?? this.isPremium,
      billingAvailable: billingAvailable ?? this.billingAvailable,
      isLoading: isLoading ?? this.isLoading,
      purchasePending: purchasePending ?? this.purchasePending,
      productPrice: productPrice ?? this.productPrice,
      ready: ready ?? this.ready,
      error: clearError ? null : (error ?? this.error),
    );
  }

  factory PremiumState.initial() {
    return const PremiumState(
      isPremium: false,
      billingAvailable: false,
      isLoading: true,
      purchasePending: false,
      productPrice: AppConstants.premiumPriceFallback,
      ready: false,
      error: null,
    );
  }
}

class PremiumController extends StateNotifier<PremiumState> {
  PremiumController({
    required LocalStorageService storage,
    required PremiumBillingService billingService,
  })  : _storage = storage,
        _billingService = billingService,
        super(PremiumState.initial()) {
    _init();
  }

  final LocalStorageService _storage;
  final PremiumBillingService _billingService;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  ProductDetails? _premiumProduct;
  Completer<PremiumPurchaseResult>? _purchaseCompleter;

  Future<void> _init() async {
    final storedPremium =
        _storage.getBool(StorageKeys.premiumUnlocked) ?? false;

    if (!mounted) return;
    state = state.copyWith(
      isPremium: storedPremium,
      isLoading: true,
      ready: false,
      clearError: true,
    );

    _purchaseSub = _billingService.purchaseStream.listen(
      (purchases) {
        unawaited(_handlePurchaseUpdates(purchases));
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        state = state.copyWith(
          purchasePending: false,
          error: 'Billing error: ${_friendlyError(error)}',
        );
        _completePurchaseResult(PremiumPurchaseResult.failed);
      },
    );

    final billingSnapshot =
        await _loadBillingSnapshot(triggerRestore: true, surfaceUnavailable: true);
    if (!mounted) return;
    developer.log(
      'Billing init available=${billingSnapshot.available} productLoaded=${billingSnapshot.product != null} error=${billingSnapshot.error ?? 'none'}',
      name: 'DeckPilot.Billing',
    );
    state = state.copyWith(
      billingAvailable: billingSnapshot.available,
      productPrice:
          billingSnapshot.product?.price ?? AppConstants.premiumPriceFallback,
      isLoading: false,
      ready: true,
      error: billingSnapshot.error,
      clearError: billingSnapshot.error == null,
    );
  }

  Future<void> refresh() async {
    final billingSnapshot =
        await _loadBillingSnapshot(triggerRestore: false, surfaceUnavailable: true);
    if (!mounted) return;
    developer.log(
      'Billing refresh available=${billingSnapshot.available} productLoaded=${billingSnapshot.product != null} error=${billingSnapshot.error ?? 'none'}',
      name: 'DeckPilot.Billing',
    );
    state = state.copyWith(
      billingAvailable: billingSnapshot.available,
      productPrice:
          billingSnapshot.product?.price ?? AppConstants.premiumPriceFallback,
      error: billingSnapshot.error,
      clearError: billingSnapshot.error == null,
    );
  }

  Future<PremiumPurchaseResult> purchasePremium() async {
    if (state.isPremium) return PremiumPurchaseResult.alreadyPremium;

    if (!state.billingAvailable || _premiumProduct == null) {
      state = state.copyWith(
        error: !state.billingAvailable
            ? _billingUnavailableMessage()
            : _missingProductMessage(),
      );
      return PremiumPurchaseResult.unavailable;
    }

    if (_purchaseCompleter != null && !_purchaseCompleter!.isCompleted) {
      return _purchaseCompleter!.future;
    }

    _purchaseCompleter = Completer<PremiumPurchaseResult>();
    state = state.copyWith(purchasePending: true, clearError: true);

    try {
      final started = await _billingService.buyOneTime(_premiumProduct!);
      developer.log(
        'Purchase flow started=$started product=${_premiumProduct!.id}',
        name: 'DeckPilot.Billing',
      );
      if (!started) {
        state = state.copyWith(purchasePending: false);
        _completePurchaseResult(PremiumPurchaseResult.cancelled);
      }
    } catch (error) {
      state = state.copyWith(
        purchasePending: false,
        error: _friendlyError(error),
      );
      _completePurchaseResult(PremiumPurchaseResult.failed);
    }

    try {
      return await _purchaseCompleter!.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          state = state.copyWith(
            purchasePending: false,
            error: 'Purchase timed out. Please try again.',
          );
          _completePurchaseResult(PremiumPurchaseResult.failed);
          return PremiumPurchaseResult.failed;
        },
      );
    } finally {
      _purchaseCompleter = null;
    }
  }

  Future<void> restorePurchases() async {
    if (!state.billingAvailable) {
      state = state.copyWith(error: _billingUnavailableMessage());
      return;
    }
    try {
      await _billingService.restorePurchases();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        error: 'Restore failed: ${_friendlyError(error)}',
      );
    }
  }

  Future<_BillingSnapshot> _loadBillingSnapshot({
    required bool triggerRestore,
    required bool surfaceUnavailable,
  }) async {
    final available = await _billingService.isAvailable();
    if (!available) {
      _premiumProduct = null;
      return _BillingSnapshot(
        available: false,
        error: surfaceUnavailable ? _billingUnavailableMessage() : null,
      );
    }

    ProductDetails? product;
    String? queryError;

    try {
      final response = await _billingService
          .queryProducts(<String>{AppConstants.premiumProductId});
      if (!mounted) {
        return const _BillingSnapshot(available: false);
      }

      if (response.error != null) {
        queryError = response.error!.message;
      }

      product = response.productDetails
          .where((item) => item.id == AppConstants.premiumProductId)
          .firstOrNull;

      if (product == null) {
        queryError = queryError ?? _missingProductMessage();
      }

      _premiumProduct = product;

      if (triggerRestore) {
        // Keep license state in sync across reinstalls/device switches.
        unawaited(_billingService.restorePurchases());
      }

      return _BillingSnapshot(
        available: true,
        product: product,
        error: queryError,
      );
    } catch (error) {
      _premiumProduct = null;
      return _BillingSnapshot(
        available: true,
        error: 'Billing catalog failed to load: ${_friendlyError(error)}',
      );
    }
  }

  String _billingUnavailableMessage() {
    if (kIsWeb) {
      return 'In-app purchases are unavailable in the web build.';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Google Play billing is unavailable on this device. Use a Play Store-enabled Android device or emulator signed into Google Play.';
      case TargetPlatform.iOS:
        return 'App Store purchases are unavailable on this device.';
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return 'In-app purchases are unavailable on this desktop build.';
      case TargetPlatform.fuchsia:
        return 'In-app purchases are unavailable on this device.';
    }
  }

  String _missingProductMessage() {
    const productId = AppConstants.premiumProductId;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        AppConstants.androidApplicationId.startsWith('com.example.')) {
      return 'Google Play did not return product $productId. The Android package ID is still ${AppConstants.androidApplicationId}, which must match a real Play Console app before billing will work.';
    }

    return 'The premium product $productId was not returned by the store. Verify that it is active for this app build.';
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!mounted) return;
      developer.log(
        'Purchase update product=${purchase.productID} status=${purchase.status.name} pendingComplete=${purchase.pendingCompletePurchase}',
        name: 'DeckPilot.Billing',
      );
      if (purchase.productID != AppConstants.premiumProductId) {
        if (purchase.pendingCompletePurchase) {
          await _billingService.completePurchase(purchase);
        }
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(purchasePending: true, clearError: true);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _activatePremium();
          if (!mounted) return;
          state = state.copyWith(purchasePending: false, clearError: true);
          _completePurchaseResult(PremiumPurchaseResult.success);
          break;
        case PurchaseStatus.canceled:
          state = state.copyWith(purchasePending: false);
          _completePurchaseResult(PremiumPurchaseResult.cancelled);
          break;
        case PurchaseStatus.error:
          final error = purchase.error?.message ?? 'Purchase failed.';
          state = state.copyWith(
            purchasePending: false,
            error: error,
          );
          _completePurchaseResult(PremiumPurchaseResult.failed);
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _billingService.completePurchase(purchase);
      }
    }
  }

  Future<void> _activatePremium() async {
    if (!mounted) return;
    state = state.copyWith(isPremium: true, clearError: true);
    await _storage.setBool(StorageKeys.premiumUnlocked, true);
    await _storage.setString(
      StorageKeys.premiumUnlockedAt,
      DateTime.now().toIso8601String(),
    );
  }

  void _completePurchaseResult(PremiumPurchaseResult result) {
    final completer = _purchaseCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(result);
  }

  String _friendlyError(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) return 'Unknown error.';
    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _BillingSnapshot {
  const _BillingSnapshot({
    required this.available,
    this.product,
    this.error,
  });

  final bool available;
  final ProductDetails? product;
  final String? error;
}
