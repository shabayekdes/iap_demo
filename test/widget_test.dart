import 'package:flutter_test/flutter_test.dart';

import 'package:iap_demo/main.dart';

void main() {
  testWidgets('Home screen shows app title', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // The store is not available in a unit-test environment, so the app
    // renders its loading indicator first. We just verify the app bar
    // title is present.
    expect(find.text('IAP Demo'), findsOneWidget);
  });
}
