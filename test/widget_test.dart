// Smoke tests for Khaata.
//
// These run against the real local database, so they also prove the
// no-login bootstrap path works: the app must seed its default categories
// and accounts and reach the ledger without any sign-in step.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/core/constants.dart';

void main() {
  testWidgets('app boots straight into the ledger with no login', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KhaataApp()));
    await tester.pumpAndSettle();

    // The four bottom-nav destinations should be present...
    expect(find.text('Trans.'), findsOneWidget);
    expect(find.text('Stats'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // ...and no sign-in surface anywhere.
    expect(find.text('Log in'), findsNothing);
    expect(find.text('Sign up'), findsNothing);
  });

  testWidgets('home shows the five ledger tabs', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KhaataApp()));
    await tester.pumpAndSettle();

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
  });

  test('currency defaults to rupees', () {
    expect(kCurrencySymbol, '₹');
    expect(kAppName, 'Khaata');
  });
}
