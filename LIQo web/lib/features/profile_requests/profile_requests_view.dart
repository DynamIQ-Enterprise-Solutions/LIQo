import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../shared/lists/list_scaffold.dart';
import '../../shared/widgets/common.dart' show Pill, PillKind;
import '../accounts/accounts_service.dart' show roleLabels;
import '../account/profile_service.dart';

/// Status of a profile change request as a pill.
class RequestStatusPill extends StatelessWidget {
  const RequestStatusPill(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) => switch (status) {
        'pending' => const Pill('Waiting', kind: PillKind.pending),
        'approved' => const Pill('Approved', kind: PillKind.green),
        'rejected' => const Pill('Rejected', kind: PillKind.off),
        'cancelled' => const Pill('Cancelled', kind: PillKind.off),
        _ => Pill(status, kind: PillKind.off),
      };
}

/// Superadmin: people's requests to change their own name and email, as the
/// "Profile changes" tab of Requests & reports (Round 19).
class ProfileRequestsList extends ConsumerStatefulWidget {
  const ProfileRequestsList({super.key});

  @override
  ConsumerState<ProfileRequestsList> createState() => _ProfileRequestsListState();
}

class _ProfileRequestsListState extends ConsumerState<ProfileRequestsList> {
  final _list = ListController();
  final _service = ProfileService();
  static final _fmt = DateFormat('MMM d, yyyy h:mm a');

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListScaffold<ProfileRequest>(
      controller: _list,
      fetch: _service.list,
      searchHint: 'Search…',
      emptyText: 'No requests here.',
      onRowTap: (r) => context.go('/superadmin/profile-requests/${r.id}'),
      filters: const [
        FilterSpec(name: 'status', label: 'Waiting', options: {'': 'Waiting', 'approved': 'Approved', 'rejected': 'Rejected', 'cancelled': 'Cancelled', 'all': 'All'}),
      ],
      columns: [
        ListColumn(
          label: 'Person',
          flex: 3,
          cell: (c, r) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.currentName, style: ts(12, w: FontWeight.w700, color: p.ink)),
              Text(roleLabels[r.role] ?? r.role, style: ts(11, color: p.muted)),
            ],
          ),
        ),
        ListColumn(
          label: 'Requested',
          flex: 4,
          cell: (c, r) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.requestedName, style: ts(12, w: r.pending && r.nameChanged ? FontWeight.w700 : FontWeight.w400, color: p.ink)),
              Text(r.requestedEmail, style: ts(11, color: r.pending && r.emailChanged ? p.brand2 : p.muted)),
            ],
          ),
        ),
        ListColumn(label: 'Sent', flex: 2, hideOnMobile: true, cell: (c, r) => Text(_fmt.format(r.createdAt), style: ts(11, color: p.muted))),
        ListColumn(label: 'Status', flex: 2, cell: (c, r) => Align(alignment: Alignment.centerLeft, child: RequestStatusPill(r.status))),
      ],
    );
  }
}
