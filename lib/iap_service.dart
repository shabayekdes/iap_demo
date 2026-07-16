import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Product IDs. These must match the IDs configured in the StoreKit
/// configuration file (for local testing) and in App Store Connect
/// (for sandbox / production).
class IapProducts {
  static const String coins = 'MAPNEIGHBORHOODS'; // consumable (approved in App Store Connect)
  static const String monthPass =
      'app.sumaya369.net.month_pass'; // non-renewing subscription

  static const Set<String> ids = {coins, monthPass};
}

/// Prefix every line so device logs can be filtered from the noise, e.g.
///   idevicesyslog | grep IAP
void _log(String message) => debugPrint('[IAP] $message');

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

  /// IDs the store did not recognise. Almost always means the product is
  /// missing from App Store Connect / the StoreKit config, or is not yet
  /// cleared for sale. Surfaced in the UI so the failure isn't silent.
  List<String> notFoundIds = [];

  /// Product ID currently being purchased (drives per-button spinners),
  /// or null when no purchase is in flight.
  String? purchasingId;

  /// Human-readable status of the last purchase attempt (success / error),
  /// consumed by the UI to show a SnackBar.
  String? lastMessage;

  Future<void> init() async {
    _log('init() starting on ${defaultTargetPlatform.name}');

    // Listen to the purchase stream BEFORE making any purchase so we never
    // miss an update (including transactions restored on launch).
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () {
        _log('purchaseStream closed');
        _subscription?.cancel();
      },
      onError: (Object e) {
        _log('purchaseStream ERROR: $e');
        lastMessage = 'Purchase stream error: $e';
        notifyListeners();
      },
    );
    _log('purchaseStream listener attached');

    available = await _iap.isAvailable();
    _log('isAvailable() -> $available');
    if (!available) {
      _log('store unreachable; no sandbox account signed in, or the device '
          'cannot reach the store. Aborting product query.');
      loading = false;
      notifyListeners();
      return;
    }

    _log('querying ${IapProducts.ids.length} product id(s): ${IapProducts.ids}');
    final ProductDetailsResponse response =
        await _iap.queryProductDetails(IapProducts.ids);

    if (response.error != null) {
      final IAPError e = response.error!;
      _log('query ERROR: code=${e.code} source=${e.source} '
          'message=${e.message} details=${e.details}');
      lastMessage = 'Failed to load products: ${e.message}';
    }

    _log('query returned ${response.productDetails.length} product(s), '
        '${response.notFoundIDs.length} not found');
    for (final ProductDetails p in response.productDetails) {
      _log('  FOUND id=${p.id} title="${p.title}" price=${p.price} '
          'raw=${p.rawPrice} currency=${p.currencyCode}');
    }
    for (final String id in response.notFoundIDs) {
      // Usually means the IDs aren't configured in StoreKit / App Store Connect.
      _log('  NOT FOUND id=$id (missing in App Store Connect, or not cleared '
          'for sale)');
    }

    products = response.productDetails;
    notFoundIds = response.notFoundIDs;
    loading = false;
    _log('init() done: available=$available products=${products.length}');
    notifyListeners();
  }

  /// Starts a purchase. `buyConsumable` is the correct call for both the
  /// consumable and the iOS non-renewing subscription in this demo.
  Future<void> buy(ProductDetails product) async {
    _log('buy() id=${product.id} price=${product.price}');
    purchasingId = product.id;
    lastMessage = null;
    notifyListeners();

    final PurchaseParam param = PurchaseParam(productDetails: product);
    try {
      final bool started = await _iap.buyConsumable(purchaseParam: param);
      _log('buyConsumable() accepted=$started for ${product.id}');
    } catch (e, stack) {
      _log('buyConsumable() THREW for ${product.id}: $e');
      _log('$stack');
      purchasingId = null;
      lastMessage = 'Could not start purchase: $e';
      notifyListeners();
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    _log('purchaseStream fired with ${purchases.length} update(s)');

    for (final PurchaseDetails purchase in purchases) {
      _log('  update id=${purchase.productID} status=${purchase.status.name} '
          'purchaseID=${purchase.purchaseID} '
          'txDate=${purchase.transactionDate} '
          'pendingComplete=${purchase.pendingCompletePurchase}');

      switch (purchase.status) {
        case PurchaseStatus.pending:
          // Transaction in progress — keep the spinner up.
          purchasingId = purchase.productID;
          break;

        case PurchaseStatus.error:
          final IAPError? e = purchase.error;
          _log('  PURCHASE ERROR code=${e?.code} source=${e?.source} '
              'message=${e?.message} details=${e?.details}');
          purchasingId = null;
          lastMessage = 'Purchase failed: ${e?.message ?? 'unknown error'}';
          break;

        case PurchaseStatus.canceled:
          _log('  purchase canceled by user');
          purchasingId = null;
          lastMessage = 'Purchase canceled.';
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // In production: verify purchase.verificationData server-side
          // BEFORE granting anything. Here we grant locally for the demo.
          _log('  PURCHASE OK id=${purchase.productID} '
              'source=${purchase.verificationData.source} '
              'receiptLen=${purchase.verificationData.serverVerificationData.length}');
          purchasingId = null;
          lastMessage = 'Purchased ${purchase.productID} 🎉';
          break;
      }

      // Always finish the transaction, otherwise the store keeps
      // re-delivering it and consumables can't be bought again.
      if (purchase.pendingCompletePurchase) {
        _log('  completePurchase() for ${purchase.productID}');
        _iap.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _log('dispose()');
    _subscription?.cancel();
    super.dispose();
  }
}
