import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'iap_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IAP Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final IapService _iap = IapService();
  String? _shownMessage;

  @override
  void initState() {
    super.initState();
    _iap.addListener(_onIapChanged);
    _iap.init();
  }

  void _onIapChanged() {
    // Surface any new status message as a SnackBar, once.
    final String? msg = _iap.lastMessage;
    if (msg != null && msg != _shownMessage) {
      _shownMessage = msg;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(msg)));
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _iap.removeListener(_onIapChanged);
    _iap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IAP Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_iap.loading) {
      return const CircularProgressIndicator();
    }

    if (!_iap.available) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Store not available.\n\nRun on a real device or iOS Simulator with a '
          'StoreKit configuration attached to the run scheme.',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_iap.products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No products found.\n\nCheck that the product IDs exist in your '
          'StoreKit config / App Store Connect.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      shrinkWrap: true,
      children: [
        const Text(
          'Tap a button to purchase',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        for (final ProductDetails product in _iap.products)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _BuyButton(
              product: product,
              busy: _iap.purchasingId == product.id,
              onPressed: () => _iap.buy(product),
            ),
          ),
      ],
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({
    required this.product,
    required this.busy,
    required this.onPressed,
  });

  final ProductDetails product;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text('${product.title} — ${product.price}'),
    );
  }
}
