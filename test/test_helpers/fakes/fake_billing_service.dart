import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:obs_stream_deck/core/constants/app_constants.dart';
import 'package:obs_stream_deck/core/services/premium_billing_service.dart';

class FakeBillingService implements PremiumBillingService {
  FakeBillingService({
    this.available = true,
    this.price = r'$4.99',
    this.purchaseStarts = true,
    this.returnProduct = true,
    this.queryErrorMessage,
  });

  final StreamController<List<PurchaseDetails>> _purchaseStreamController =
      StreamController<List<PurchaseDetails>>.broadcast();

  bool available;
  String price;
  bool purchaseStarts;
  bool returnProduct;
  String? queryErrorMessage;
  int restoreCalls = 0;
  int buyCalls = 0;
  int completeCalls = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _purchaseStreamController.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> productIds) async {
    return ProductDetailsResponse(
      productDetails: returnProduct
          ? <ProductDetails>[
              ProductDetails(
                id: AppConstants.premiumProductId,
                title: 'DeckPilot Premium',
                description: 'Unlock premium features',
                price: price,
                rawPrice: 4.99,
                currencyCode: 'USD',
                currencySymbol: r'$',
              ),
            ]
          : const <ProductDetails>[],
      notFoundIDs: returnProduct
          ? const <String>[]
          : const <String>[AppConstants.premiumProductId],
      error: queryErrorMessage == null
          ? null
          : IAPError(
              source: 'test',
              code: 'query_failed',
              message: queryErrorMessage!,
            ),
    );
  }

  @override
  Future<bool> buyOneTime(ProductDetails product) async {
    buyCalls += 1;
    return purchaseStarts;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls += 1;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completeCalls += 1;
  }

  void emitPurchased() {
    final purchase = PurchaseDetails(
      productID: AppConstants.premiumProductId,
      purchaseID: 'purchase_1',
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local',
        serverVerificationData: 'server',
        source: 'test',
      ),
      transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
      status: PurchaseStatus.purchased,
    )..pendingCompletePurchase = true;

    _purchaseStreamController.add(<PurchaseDetails>[purchase]);
  }

  void emitRestored() {
    final purchase = PurchaseDetails(
      productID: AppConstants.premiumProductId,
      purchaseID: 'restore_1',
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local',
        serverVerificationData: 'server',
        source: 'test',
      ),
      transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
      status: PurchaseStatus.restored,
    )..pendingCompletePurchase = true;

    _purchaseStreamController.add(<PurchaseDetails>[purchase]);
  }

  void emitCancelled() {
    final purchase = PurchaseDetails(
      productID: AppConstants.premiumProductId,
      purchaseID: 'cancel_1',
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local',
        serverVerificationData: 'server',
        source: 'test',
      ),
      transactionDate: null,
      status: PurchaseStatus.canceled,
    );

    _purchaseStreamController.add(<PurchaseDetails>[purchase]);
  }

  void dispose() {
    _purchaseStreamController.close();
  }
}
