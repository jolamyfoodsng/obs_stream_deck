import 'package:in_app_purchase/in_app_purchase.dart';

class PremiumBillingService {
  PremiumBillingService({InAppPurchase? inAppPurchase})
      : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;

  Future<bool> isAvailable() {
    return _inAppPurchase.isAvailable();
  }

  Future<ProductDetailsResponse> queryProducts(Set<String> productIds) {
    return _inAppPurchase.queryProductDetails(productIds);
  }

  Future<bool> buyOneTime(ProductDetails product) {
    final param = PurchaseParam(productDetails: product);
    return _inAppPurchase.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() {
    return _inAppPurchase.restorePurchases();
  }

  Future<void> completePurchase(PurchaseDetails purchase) {
    return _inAppPurchase.completePurchase(purchase);
  }
}
