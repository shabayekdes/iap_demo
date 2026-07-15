import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Product IDs. These must match the IDs configured in the StoreKit
/// configuration file (for local testing) and in App Store Connect
/// (for sandbox / production).
class IapProducts {
  static const String coins = 'com.example.iap_demo.coins'; // consumable
  static const String monthPass =
      'com.example.iap_demo.month_pass'; // non-renewing subscription

  static const Set<String> ids = {coins, monthPass};
}

/// Wraps [InAppPurchase] and exposes a small [ChangeNotifier] API the UI
/// can listen to. Handles loading products and the purchase lifecycle.
///
/// On iOS the official plugin treats a *consumable* and a *non-renewing
/// subscription* the same way: both are bought with [buy] (which calls
/// `buyConsumable`) and then finished with `completePurchase`.
class IapService extends ChangeNotifier {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// Whether the store is reachable on this device.
  bool available = false;

  /// True while products are being loaded.
  bool loading = true;

  /// Products successfully fetched from the store.
  List<ProductDetails> products = [];

  /// Product ID currently being purchased (drives per-button spinners),
  /// or null when no purchase is in flight.
  String? purchasingId;

  /// Human-readable status of the last purchase attempt (success / error),
  /// consumed by the UI to show a SnackBar.
  String? lastMessage;

  Future<void> init() async {
    // Listen to the purchase stream BEFORE making any purchase so we never
    // miss an update (including transactions restored on launch).
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (Object e) {
        lastMessage = 'Purchase stream error: $e';
        notifyListeners();
      },
    );

    available = await _iap.isAvailable();
    if (!available) {
      loading = false;
      notifyListeners();
      return;
    }

    final ProductDetailsResponse response =
        await _iap.queryProductDetails(IapProducts.ids);

    if (response.error != null) {
      lastMessage = 'Failed to load products: ${response.error!.message}';
    }
    if (response.notFoundIDs.isNotEmpty) {
      // Usually means the IDs aren't configured in StoreKit / App Store Connect.
      debugPrint('Products not found: ${response.notFoundIDs}');
    }

    products = response.productDetails;
    loading = false;
    notifyListeners();
  }

  /// Starts a purchase. `buyConsumable` is the correct call for both the
  /// consumable and the iOS non-renewing subscription in this demo.
  Future<void> buy(ProductDetails product) async {
    purchasingId = product.id;
    lastMessage = null;
    notifyListeners();

    final PurchaseParam param = PurchaseParam(productDetails: product);
    try {
      await _iap.buyConsumable(purchaseParam: param);
    } catch (e) {
      purchasingId = null;
      lastMessage = 'Could not start purchase: $e';
      notifyListeners();
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final PurchaseDetails purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          // Transaction in progress — keep the spinner up.
          purchasingId = purchase.productID;
          break;

        case PurchaseStatus.error:
          purchasingId = null;
          lastMessage = 'Purchase failed: ${purchase.error?.message ?? 'unknown error'}';
          break;

        case PurchaseStatus.canceled:
          purchasingId = null;
          lastMessage = 'Purchase canceled.';
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // In production: verify purchase.verificationData server-side
          // BEFORE granting anything. Here we grant locally for the demo.
          purchasingId = null;
          lastMessage = 'Purchased ${purchase.productID} 🎉';
          break;
      }

      // Always finish the transaction, otherwise the store keeps
      // re-delivering it and consumables can't be bought again.
      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
