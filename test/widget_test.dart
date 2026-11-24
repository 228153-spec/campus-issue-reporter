// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssw3401_lab/second_page.dart';

void main() {
  test('basic sanity check', () {
    expect(1 + 1, 2);
  });

  testWidgets('SecondPage shows the form fields and buttons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SecondPage()));

    expect(find.text('What did you lend?'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('SecondPage warns when fields are empty', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SecondPage()));

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Please fill in both fields'), findsOneWidget);
  });
}