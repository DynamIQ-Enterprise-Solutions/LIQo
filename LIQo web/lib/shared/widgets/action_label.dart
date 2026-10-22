/// Audit actions in plain words, for the overview's recent activity and the
/// audit log (Round 14; closes the superadmin review's "readable action names").
/// The code itself stays visible in the audit log's details.
const _labels = <String, String>{
  'login_success': 'Signed in',
  'login_failed': 'Sign-in failed',
  'login_blocked_inactive': 'Sign-in blocked (account inactive)',
  'login_blocked_locked': 'Sign-in blocked (account locked)',
  'logout': 'Signed out',
  'account_locked': 'Account locked after failed sign-ins',
  'password_changed': 'Changed their password',
  'password_reset_by_admin': 'Reset a password',
  'account_created': 'Created an account',
  'account_updated': 'Edited an account',
  'account_deactivated': 'Deactivated an account',
  'account_reactivated': 'Reactivated an account',
  'superadmin_created': 'Created a superadmin',
  'superadmin_deactivated': 'Deactivated a superadmin',
  'superadmin_reactivated': 'Reactivated a superadmin',
  'superadmin_password_reset': 'Reset a superadmin\'s password',
  'profile_updated': 'Updated their own profile',
  'profile_change_requested': 'Asked to change their profile',
  'profile_change_cancelled': 'Profile change request cancelled',
  'profile_change_approved': 'Approved a profile change',
  'profile_change_rejected': 'Rejected a profile change',
  'reports_to_recomputed': 'Admin superiors updated automatically',
  'mall_created': 'Created a mall',
  'mall_updated': 'Edited a mall',
  'mall_deactivated': 'Deactivated a mall',
  'mall_reactivated': 'Reactivated a mall',
  'mall_owner_added': 'Added a mall owner',
  'mall_owner_removed': 'Removed a mall owner',
  'branch_created': 'Created a branch',
  'branch_updated': 'Edited a branch',
  'branch_deactivated': 'Deactivated a branch',
  'branch_reactivated': 'Reactivated a branch',
  'supervisor_assignments_updated': 'Changed a mall owner\'s malls',
  'mall_admin_assignments_updated': 'Placed a mall admin',
  'mall_admin_removed_from_mall': 'Removed a mall admin from a mall',
  'store_created': 'Created a store',
  'store_updated': 'Edited a store',
  'store_deactivated': 'Deactivated a store',
  'store_reactivated': 'Reactivated a store',
  'store_spaces_updated': 'Linked a store to map spaces',
  'store_owner_created': 'Created a store owner',
  'store_owner_assigned': 'Gave a store to its owner',
  'store_owner_unassigned': 'Took a store from its owner',
  'option_created': 'Added a list option',
  'option_updated': 'Edited a list option',
  'option_deleted': 'Deleted a list option',
  'option_deactivated': 'Deactivated a list option',
  'option_reactivated': 'Reactivated a list option',
  'announcement_published': 'Published an announcement',
  'announcement_submitted': 'Submitted an announcement for review',
  'announcement_updated': 'Edited an announcement',
  'announcement_approved': 'Approved an announcement',
  'announcement_rejected': 'Rejected an announcement',
  'announcement_deleted': 'Deleted an announcement',
  'announcement_detached': 'Removed an announcement from their branches',
  'map_created': 'Started a map',
  'map_edited': 'Edited a map',
  'map_published': 'Published a map',
  'map_rolled_back': 'Rolled a map back',
  'map_copied': 'Copied a map',
  'map_deleted': 'Deleted a map',
  'map_converted': 'Traced walls from a floor plan',
  'map_lock_force_released': 'Released a map editing lock',
  'backdrop_uploaded': 'Uploaded a floor plan',
  'backdrop_deleted': 'Removed a floor plan',
  'settings_updated': 'Changed platform settings',
};

/// "store_created" → "Created a store". Unknown codes and raw requests
/// ("POST /api/stores") still read as words.
String actionLabel(String action) {
  final known = _labels[action];
  if (known != null) return known;
  final request = RegExp(r'^(POST|PUT|PATCH|DELETE) (\S+)').firstMatch(action);
  if (request != null) {
    final verb = switch (request.group(1)) { 'POST' => 'Created or sent', 'DELETE' => 'Deleted', _ => 'Changed' };
    final parts = request.group(2)!.split('/').where((s) => s.isNotEmpty && s != 'api' && int.tryParse(s) == null).toList();
    return '$verb ${parts.isEmpty ? 'a record' : parts.last.replaceAll('-', ' ')}';
  }
  final words = action.replaceAll('_', ' ').trim();
  return words.isEmpty ? action : '${words[0].toUpperCase()}${words.substring(1)}';
}
