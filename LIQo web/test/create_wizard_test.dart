// The create wizards (owner decisions 2026-10-22): every step shown up front,
// live checks while typing (a taken or inactive email blocks Next; a repeated
// name and an email waiting in a profile change request only warn), details
// of the matching account only for a superadmin, the admins already on a
// branch, a discard question when closing, and the password on the last step.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/accounts/accounts_service.dart';
import 'package:gabay_admin/features/accounts/assignment_dialog.dart';
import 'package:gabay_admin/features/accounts/create_account_wizard.dart';
import 'package:gabay_admin/features/stores/store_owner_wizard.dart';
import 'package:gabay_admin/features/stores/stores_service.dart';
import 'package:gabay_admin/shared/forms/wizard_dialog.dart';
import 'package:gabay_admin/shared/models/paged.dart';

import 'support/fake_api.dart';

/// Pumps a page with one button that opens [open]; the outcome lands in [result].
Future<void> _start(WidgetTester tester, String role, Future<Object?> Function(BuildContext) open, void Function(Object?) result) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: role);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(
      body: Builder(
        builder: (c) => Center(child: TextButton(onPressed: () async => result(await open(c)), child: const Text('open'))),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Lets the debounced check fire and its answer arrive.
Future<void> _checks(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String field, String text) async {
  await tester.enterText(find.descendant(of: find.byKey(ValueKey('$field-text')), matching: find.byType(TextField)), text);
  await tester.pump();
}

bool _enabled(WidgetTester tester, Key key) =>
    !tester.widget<IgnorePointer>(find.descendant(of: find.byKey(key), matching: find.byType(IgnorePointer)).first).ignoring;

Future<void> _next(WidgetTester tester, [Key key = CreateAccountWizard.nextKey]) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<PagedResult<LookupItem>> _branches(int mallId, {int pageSize = 200}) async =>
    PagedResult(items: const [LookupItem(id: 2, label: 'Short')], totalCount: 1, page: 1, pageSize: pageSize);

void main() {
  testWidgets('every step is shown up front; choosing Superadmin drops the Access step', (tester) async {
    await _start(tester, 'superadmin', (c) => runCreateAccountWizard(c), (_) {});
    for (final s in ['Role', 'Details', 'Access', 'Review', 'Done']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('STEP 1 OF 5'), findsOneWidget);
    expect(_enabled(tester, CreateAccountWizard.nextKey), isFalse, reason: 'no role chosen yet');

    await tester.tap(find.byKey(CreateAccountWizard.roleKey('superadmin')));
    await tester.pumpAndSettle();
    expect(find.text('Access'), findsNothing);
    expect(find.text('STEP 1 OF 4'), findsOneWidget);
    expect(_enabled(tester, CreateAccountWizard.nextKey), isTrue);
  });

  testWidgets('a taken email blocks Next and, for a superadmin, names who has it', (tester) async {
    await _start(tester, 'superadmin', (c) => runCreateAccountWizard(c), (_) {});
    await tester.tap(find.byKey(CreateAccountWizard.roleKey('supervisor')));
    await tester.pumpAndSettle();
    await _next(tester);
    expect(find.text('STEP 2 OF 5'), findsOneWidget);

    await _type(tester, 'fullName', 'Ana Reyes');
    await _type(tester, 'email', 'ana.taken@mall.com');
    expect(find.text('Checking this email…'), findsOneWidget);
    await _checks(tester);
    expect(find.text('Already used by $longPerson (Mall Admin).'), findsOneWidget);
    expect(find.text('Open account'), findsOneWidget);
    expect(_enabled(tester, CreateAccountWizard.nextKey), isFalse);

    await _type(tester, 'email', 'ana.reyes@mall.com');
    await _checks(tester);
    expect(find.text('Available.'), findsOneWidget);
    expect(_enabled(tester, CreateAccountWizard.nextKey), isTrue);
  });

  testWidgets('a mall owner only learns that the email is in use', (tester) async {
    await _start(tester, 'supervisor', (c) => runCreateAccountWizard(c, fixedRole: 'mall_admin'), (_) {});
    expect(find.text('Role'), findsNothing, reason: 'the role is fixed');
    expect(find.text('STEP 1 OF 4'), findsOneWidget);
    await _type(tester, 'email', 'ana.taken@mall.com');
    await _checks(tester);
    expect(find.text('This email is already in use.'), findsOneWidget);
    expect(find.text('Open account'), findsNothing);
    await _type(tester, 'email', 'ana.inactive@mall.com');
    await _checks(tester);
    expect(find.text('This email belongs to an inactive account.'), findsOneWidget);
    expect(_enabled(tester, CreateAccountWizard.nextKey), isFalse);
  });

  testWidgets('a repeated name and a requested email warn but allow; the password shows on Done', (tester) async {
    Object? outcome;
    await _start(tester, 'superadmin', (c) => runCreateAccountWizard(c), (r) => outcome = r);
    await tester.tap(find.byKey(CreateAccountWizard.roleKey('superadmin')));
    await tester.pumpAndSettle();
    await _next(tester);

    await _type(tester, 'fullName', 'Maria Santos');
    await _type(tester, 'email', 'maria.pending@mall.com');
    await _checks(tester);
    expect(find.textContaining('2 accounts already have this name'), findsOneWidget);
    expect(find.textContaining("waiting in someone's profile change request"), findsOneWidget);
    expect(_enabled(tester, CreateAccountWizard.nextKey), isTrue);

    await _next(tester);
    expect(find.text('Check and create'), findsOneWidget);
    expect(find.textContaining('will see and change everything'), findsOneWidget);
    expect(find.textContaining('2 accounts already have this name'), findsOneWidget, reason: 'warnings are repeated on Review');

    await _next(tester);
    expect(find.text('Create another superadmin?'), findsOneWidget);
    await tester.tap(find.text('Yes, create superadmin'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 4 OF 4'), findsOneWidget);
    expect(find.text('Tmp-7Kq2-Wx9p'), findsOneWidget);

    await _next(tester); // Close
    expect(find.byType(CreateAccountWizard), findsNothing);
    expect((outcome as WizardOutcome<Account>).created?.id, 77);
  });

  testWidgets('a mall admin step shows who already manages the chosen branch', (tester) async {
    await _start(
      tester,
      'superadmin',
      (c) => runCreateAccountWizard(c, fixedRole: 'mall_admin', mall: const LookupItem(id: 1, label: 'SM Prime'), branchSearch: _branches),
      (_) {},
    );
    await _type(tester, 'fullName', 'Ben Cruz');
    await _type(tester, 'email', 'ben.cruz@mall.com');
    await _checks(tester);
    await _next(tester);
    expect(find.text('Which branch do they manage?'), findsOneWidget);
    expect(_enabled(tester, CreateAccountWizard.nextKey), isFalse, reason: 'no branch yet');

    await tester.tap(find.byKey(AssignmentDialog.branchKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Short').last);
    await tester.pumpAndSettle();
    expect(find.text('This branch already has: $longPerson. A branch can have more than one admin.'), findsOneWidget);
    expect(_enabled(tester, CreateAccountWizard.nextKey), isTrue);

    await _next(tester);
    expect(find.text('SM Prime · Short'), findsOneWidget);
  });

  testWidgets('closing after typing asks first; Cancel keeps the wizard', (tester) async {
    Object? outcome = 'untouched';
    await _start(tester, 'supervisor', (c) => runCreateAccountWizard(c, fixedRole: 'mall_admin'), (r) => outcome = r);
    await _type(tester, 'fullName', 'Ana Reyes');
    await tester.tap(find.byKey(WizardFrame.closeKey));
    await tester.pumpAndSettle();
    expect(find.text('Discard this account?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.byType(CreateAccountWizard), findsOneWidget);

    await tester.tap(find.byKey(WizardFrame.closeKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateAccountWizard), findsNothing);
    expect(outcome, isNull);
  });

  testWidgets('Open account on a taken email returns that account', (tester) async {
    Object? outcome;
    await _start(tester, 'superadmin', (c) => runCreateAccountWizard(c, fixedRole: 'supervisor'), (r) => outcome = r);
    await _type(tester, 'email', 'ana.taken@mall.com');
    await _checks(tester);
    await tester.tap(find.text('Open account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect((outcome as WizardOutcome<Account>).openId, 3);
  });

  testWidgets('store owner: an existing owner gets the store added, without a new password', (tester) async {
    await _start(tester, 'mall_admin', (c) => runStoreOwnerWizard(c, store: const LookupItem(id: 1, label: 'Northline')), (_) {});
    expect(find.text('Store'), findsNothing, reason: 'the store is known');
    expect(find.text('STEP 1 OF 3'), findsOneWidget);
    await _type(tester, 'fullName', 'J. Cruz');
    await _type(tester, 'email', 'j.owner@mall.com');
    await _checks(tester);
    expect(find.textContaining('Already a store owner: $longPerson'), findsOneWidget);

    await _next(tester, StoreOwnerWizard.nextKey);
    expect(find.text('Add store'), findsOneWidget);
    await _next(tester, StoreOwnerWizard.nextKey);
    expect(find.text('Store added'), findsOneWidget);
    expect(find.textContaining('now owns Northline too'), findsOneWidget);
    expect(find.textContaining('Tmp-'), findsNothing);
  });

  testWidgets('store owner: an inactive owner is blocked, a new one gets a password', (tester) async {
    Object? outcome;
    await _start(tester, 'mall_admin', (c) => runStoreOwnerWizard(c), (r) => outcome = r);
    expect(find.text('STEP 1 OF 4'), findsOneWidget);
    await tester.tap(find.text('Choose a store…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Short').last);
    await tester.pumpAndSettle();
    await _next(tester, StoreOwnerWizard.nextKey);

    await _type(tester, 'fullName', 'J. Cruz');
    await _type(tester, 'email', 'sleepy@mall.com');
    await _checks(tester);
    expect(find.textContaining('This store owner is inactive'), findsOneWidget);
    expect(find.text('Open store owner'), findsOneWidget);
    expect(_enabled(tester, StoreOwnerWizard.nextKey), isFalse);

    await _type(tester, 'email', 'new.person@mall.com');
    await _checks(tester);
    await _next(tester, StoreOwnerWizard.nextKey);
    await _next(tester, StoreOwnerWizard.nextKey);
    expect(find.text('Store owner created'), findsOneWidget);
    expect(find.text('Tmp-3Hs8-Lm4c'), findsOneWidget);
    await tester.tap(find.text('Open store owner'));
    await tester.pumpAndSettle();
    expect((outcome as WizardOutcome<StoreOwner>).openId, 4);
  });
}
