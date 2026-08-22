import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:esep/main.dart';

void main() {
  testWidgets('App starts without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const EsepApp());
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
