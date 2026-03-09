import 'package:in_app_purchase/in_app_purchase.dart';

abstract class PremiumBillingService {
  Stream<List<PurchaseDetails>> get purchaseStream;

  Future<bool> isAvailable();

  Future<ProductDetailsResponse> queryProducts(Set<String> productIds);

  Future<bool> buyOneTime(ProductDetails product);

  Future<void> restorePurchases();

  Future<void> completePurchase(PurchaseDetails purchase);
}

class InAppPurchasePremiumBillingService implements PremiumBillingService {
  InAppPurchasePremiumBillingService({InAppPurchase? inAppPurchase})
      : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;

  @override
  Future<bool> isAvailable() {
    return _inAppPurchase.isAvailable();
  }

  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> productIds) {
    return _inAppPurchase.queryProductDetails(productIds);
  }

  @override
  Future<bool> buyOneTime(ProductDetails product) {
    final param = PurchaseParam(productDetails: product);
    return _inAppPurchase.buyNonConsumable(purchaseParam: param);
  }

  @override
  Future<void> restorePurchases() {
    return _inAppPurchase.restorePurchases();
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) {
    return _inAppPurchase.completePurchase(purchase);
  }
}
