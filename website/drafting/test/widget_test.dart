import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drafting/main.dart';

void main() {
  testWidgets('App loads splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DraftingApp());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
