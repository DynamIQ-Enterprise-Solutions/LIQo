// Round 4, updated in Round 14: who an admin reports to is set automatically
// (owner decision 2026-10-22), so no screen offers a picker for it; the Access
// cell says who an admin reports to, and no screen still says "Supervisor".

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/accounts/accounts_service.dart';
import 'package:gabay_admin/features/accounts/accounts_view.dart';
import 'package:gabay_admin/features/accounts/assignment_dialog.dart';
import 'package:gabay_admin/shared/models/paged.dart';

Widget _wrap(Widget child) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: child)));

Future<PagedResult<LookupItem>> _noBranches(int mallId, {int pageSize = 200}) async => PagedResult(items: const [], totalCount: 0, page: 1, pageSize: pageSize);

void main() {
  testWidgets('placing a mall admin has no Reports-to picker; it says the superior is set automatically', (tester) async {
    await tester.pumpWidget(_wrap(AssignmentDialog(
      role: 'mall_admin',
      title: 'Assignments',
      submitLabel: 'Save',
      initial: const AccountAssignments(branches: [AssignedBranch(id: 1, name: 'Cebu', mallId: 5, mallName: 'Ayala')]),
      branchSearch: _noBranches,
      onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Reports to'), findsNothing);
    expect(find.textContaining('set automatically'), findsOneWidget);
  });

  testWidgets('an owner placing an admin in a mall with no branches is told to ask a superadmin', (tester) async {
    await tester.pumpWidget(_wrap(AssignmentDialog(
      role: 'mall_admin',
      title: 'Assignments',
      submitLabel: 'Save',
      initialMall: const LookupItem(id: 5, label: 'Ayala'),
      canCreateBranches: false,
      branchSearch: _noBranches,
      onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('This mall has no branches yet. Ask a superadmin to add one.'), findsOneWidget);
  });

  testWidgets('Access cell names the owner or shows No owner for mall admins', (tester) async {
    const owned = Account(id: 1, email: 'a@x.y', fullName: 'A', role: 'mall_admin', isActive: true, mustChangePassword: false, access: AccountAccess(branches: 3), reportsTo: ReportsTo(id: 9, name: 'Maria Santos'));
    const unowned = Account(id: 2, email: 'b@x.y', fullName: 'B', role: 'mall_admin', isActive: true, mustChangePassword: false, access: AccountAccess(branches: 1));
    await tester.pumpWidget(_wrap(const Column(children: [AccountAccessCell(owned), AccountAccessCell(unowned), AccountAccessCell(unowned, showOwner: false)])));
    expect(find.text('reports to Maria Santos'), findsOneWidget);
    expect(find.text('No owner'), findsOneWidget, reason: 'hidden on the owner\'s own list');
  });

  test('no screen text still says Supervisor (the role is called Mall owner)', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        // A string literal that contains the word with a capital S is user-facing text.
        if (RegExp(r"'[^']*Supervisor[^']*'").hasMatch(line)) offenders.add('${f.path}:${i + 1}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
