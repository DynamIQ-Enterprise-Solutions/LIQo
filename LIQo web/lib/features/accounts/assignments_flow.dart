import 'package:flutter/material.dart';

import 'accounts_service.dart';
import 'assignment_dialog.dart';

/// The Assignments dialog for an existing account. Returns true when saved.
/// Throws when the current assignments cannot be read.
Future<bool> runAssignmentsFlow(BuildContext context, AccountsService service, Account a, {required bool isSuper}) async {
  final (_, current) = await service.get(a.id);
  if (!context.mounted) return false;
  final isOwnerRole = a.role == 'supervisor';
  return showAssignmentDialog(
    context: context,
    role: a.role,
    title: 'Assignments for ${a.fullName}',
    subtitle: isOwnerRole
        ? 'Saving replaces the whole set. A whole-mall assignment covers every branch of that mall.'
        : 'A mall admin manages exactly one branch. Picking another branch replaces it.',
    submitLabel: 'Save',
    initial: current,
    canCreateBranches: isSuper,
    onSubmit: (choice) async {
      if (isOwnerRole) {
        await service.setSupervisorAssignments(a.id, mallIds: choice.mallIds, branchIds: choice.branchIds);
      } else {
        // Who they report to follows the new branch automatically.
        await service.setMallAdminAssignments(a.id, branchIds: choice.branchIds);
      }
    },
  );
}
