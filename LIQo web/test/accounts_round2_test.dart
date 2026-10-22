// Round 2 (Superadmin) and the one-branch rule: the assignment dialog only
// allows Create / Save once something is chosen, and the Access column flags
// accounts with no access.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/accounts/accounts_service.dart';
import 'package:gabay_admin/features/accounts/accounts_view.dart';
import 'package:gabay_admin/features/accounts/assignment_dialog.dart';
import 'package:gabay_admin/shared/models/paged.dart';

const _mallId = 5;
const _branch = AssignedBranch(id: 11, name: 'Ayala Center Cebu', mallId: _mallId, mallName: 'Ayala Center');

/// Stands in for `/lookups/branches?parentId=`: one branch under mall 5, none elsewhere.
Future<PagedResult<LookupItem>> _fakeBranches(int mallId, {int pageSize = 200}) async {
  final items = mallId == _mallId ? const [LookupItem(id: 11, label: 'Ayala Center · Ayala Center Cebu')] : const <LookupItem>[];
  return PagedResult(items: items.take(pageSize).toList(), totalCount: items.length, page: 1, pageSize: pageSize);
}

Widget _wrap(Widget child) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: child));

bool _submitEnabled(WidgetTester tester) => !tester.widget<IgnorePointer>(find.byKey(AssignmentDialog.submitKey)).ignoring;

void main() {
  testWidgets('mall admin variant: Create needs the one branch', (tester) async {
    var submitted = false;
    await tester.pumpWidget(_wrap(AssignmentDialog(
      role: 'mall_admin',
      title: 'Create account',
      submitLabel: 'Create',
      initialMall: const LookupItem(id: _mallId, label: 'Ayala Center'),
      branchSearch: _fakeBranches,
      onSubmit: (_) async => submitted = true,
    )));
    await tester.pumpAndSettle();
    expect(_submitEnabled(tester), isFalse, reason: 'no branch chosen yet');
    expect(find.text('Choose the branch.'), findsOneWidget);
    expect(find.text('A mall admin manages exactly one branch. Picking another branch replaces it.'), findsOneWidget);

    await tester.pumpWidget(_wrap(AssignmentDialog(
      key: const ValueKey('with-branch'),
      role: 'mall_admin',
      title: 'Create account',
      submitLabel: 'Create',
      initial: const AccountAssignments(branches: [_branch]),
      branchSearch: _fakeBranches,
      onSubmit: (_) async => submitted = true,
    )));
    await tester.pumpAndSettle();
    expect(_submitEnabled(tester), isTrue);
    expect(find.text('Ayala Center Cebu'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(submitted, isTrue);
  });

  testWidgets('mall admin variant: a mall with no branches blocks Create and says why', (tester) async {
    await tester.pumpWidget(_wrap(AssignmentDialog(
      role: 'mall_admin',
      title: 'Create account',
      submitLabel: 'Create',
      initialMall: const LookupItem(id: 77, label: 'Empty Mall'),
      branchSearch: _fakeBranches,
      onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();
    expect(_submitEnabled(tester), isFalse);
    expect(find.text('This mall has no branches yet. Create one under Malls & branches first.'), findsOneWidget);
  });

  testWidgets('owner variant: Create needs a mall or a branch', (tester) async {
    await tester.pumpWidget(_wrap(AssignmentDialog(
      role: 'supervisor',
      title: 'Create account',
      submitLabel: 'Create',
      branchSearch: _fakeBranches,
      onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();
    expect(_submitEnabled(tester), isFalse);
    expect(find.text('Choose at least one mall or branch.'), findsOneWidget);

    await tester.pumpWidget(_wrap(AssignmentDialog(
      key: const ValueKey('with-mall'),
      role: 'supervisor',
      title: 'Create account',
      submitLabel: 'Create',
      initial: const AccountAssignments(malls: [LookupItem(id: _mallId, label: 'Ayala Center')]),
      branchSearch: _fakeBranches,
      onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();
    expect(_submitEnabled(tester), isTrue);
    expect(find.textContaining('A whole-mall assignment also covers branches created later.'), findsOneWidget);
  });

  testWidgets('Access column shows the Unassigned pill only when every count is zero', (tester) async {
    const orphan = Account(
      id: 1, email: 'o@x.y', fullName: 'Orphan', role: 'mall_admin', isActive: true, mustChangePassword: true,
      access: AccountAccess(),
    );
    const assigned = Account(
      id: 2, email: 'a@x.y', fullName: 'Assigned', role: 'supervisor', isActive: true, mustChangePassword: false,
      access: AccountAccess(malls: 1, branches: 2),
    );
    await tester.pumpWidget(_wrap(const Column(children: [AccountAccessCell(orphan, showOwner: false), AccountAccessCell(assigned)])));
    await tester.pumpAndSettle();
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('Mall-wide 1 · Branches 2'), findsOneWidget);
  });
}
