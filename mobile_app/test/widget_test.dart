import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_handler/main.dart';

void main() {
  testWidgets('App launches without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const MoneyHandlerApp());
    await tester.pump();
    // No SharedPreferences/DB plugin is available in the widget-test
    // environment, so HomeScreen just stays on its loading spinner here -
    // this only asserts the widget tree builds cleanly.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
