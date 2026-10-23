import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/lists/list_scaffold.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import 'announcements_service.dart';

List<FieldSpec> announcementFields({required bool owner}) => [
      const FieldSpec(name: 'title', label: 'Title', required: true, maxLength: 200, hint: 'e.g. Extended weekend hours'),
      const FieldSpec(name: 'body', label: 'Message', kind: FieldKind.multiline, required: true, maxLength: 5000),
      const FieldSpec(name: 'startsOn', label: 'Start date', kind: FieldKind.date, required: true),
      const FieldSpec(name: 'endsOn', label: 'End date', kind: FieldKind.date, required: true),
      const FieldSpec(name: 'imageUrl', label: 'Image URL', maxLength: 500, hint: 'https://…', help: 'Optional. Image upload comes later.'),
      if (owner)
        const FieldSpec(name: 'store', label: 'Store', kind: FieldKind.lookup, lookup: 'stores', required: true, hint: 'Choose your store…')
      else
        const FieldSpec(name: 'branches', label: 'Target branches', kind: FieldKind.multiLookup, lookup: 'branches', required: true, hint: 'Add branches…'),
    ];

Map<String, Object?> announcementBody(Map<String, Object?> v, {required bool owner}) => {
      'title': v['title'],
      'body': v['body'],
      'startsOn': v['startsOn'],
      'endsOn': v['endsOn'],
      'imageUrl': v['imageUrl'],
      if (owner) 'storeId': (v['store'] as List<LookupItem>?)?.firstOrNull?.id,
      if (!owner) 'branchIds': <int>[for (final b in (v['branches'] as List<LookupItem>? ?? const <LookupItem>[])) b.id],
    };

/// One page for every role:
///  - mall owner / mall admin / superadmin: post to branches in scope; mall admins also review.
///  - store owner: submit for a store, track status.
/// Rows open the announcement's own page.
class AnnouncementsView extends ConsumerStatefulWidget {
  const AnnouncementsView({super.key});

  @override
  ConsumerState<AnnouncementsView> createState() => _AnnouncementsViewState();
}

class _AnnouncementsViewState extends ConsumerState<AnnouncementsView> {
  final _list = ListController();
  final _service = AnnouncementsService();

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  void _msg(String text, {bool error = false}) {
    final m = ref.read(messagesProvider.notifier);
    error ? m.showError(text) : m.showSuccess(text);
  }

  Future<void> _create() async {
    String startsOn = '';
    String endsOn = '';
    try {
      (startsOn, endsOn) = await _service.defaults();
    } catch (_) {}
    if (!mounted) return;
    final owner = ref.read(currentUserProvider)?.role == 'store_owner';
    final ok = await showAppForm(
      context: context,
      title: owner ? 'Submit announcement' : 'Post announcement',
      subtitle: owner ? 'Your mall admin reviews it before it is published.' : 'Published immediately to the chosen branches for the dates below.',
      submitLabel: owner ? 'Submit for review' : 'Publish',
      initial: {'startsOn': startsOn, 'endsOn': endsOn},
      fields: announcementFields(owner: owner),
      onSubmit: (v) => _service.create(announcementBody(v, owner: owner)),
    );
    if (ok) {
      _list.refresh();
      _msg(owner ? 'Submitted for review.' : 'Announcement published.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final me = ref.watch(currentUserProvider);
    final role = me?.role ?? '';
    final nav = navForRole(role);
    final owner = role == 'store_owner';
    final roleName = {'superadmin': 'Superadmin', 'supervisor': 'Mall owner', 'mall_admin': 'Mall admin', 'store_owner': 'Store owner'}[role] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: '$roleName / Announcements',
          title: 'Announcements',
          subtitle: owner
              ? 'Submit announcements for your stores and track their review. Click a row to open it.'
              : role == 'mall_admin'
                  ? 'Post to your branches and review store-owner submissions. Click a row to open it.'
                  : 'Post announcements to the branches in your scope. Click a row to open it.',
          actions: [
            AppButton(label: owner ? 'Submit announcement' : 'Post announcement', icon: Icons.campaign_outlined, primary: true, onPressed: _create),
          ],
        ),
        ListScaffold<Announcement>(
          controller: _list,
          fetch: _service.list,
          searchHint: 'Search title, message, author…',
          emptyText: 'No announcements yet.',
          onRowTap: (a) => context.go('${nav.prefix}/announcements/${a.id}'),
          filters: const [
            FilterSpec(name: 'status', label: 'All statuses', options: {'': 'All statuses', 'pending': 'Pending review', 'approved': 'Approved', 'rejected': 'Rejected'}),
            FilterSpec(name: 'live', label: 'Any period', options: {'': 'Any period', 'live': 'Live now'}),
          ],
          columns: [
            ListColumn(
              label: 'Announcement',
              flex: 4,
              cell: (c, a) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(a.title, style: ts(12, w: FontWeight.w700, color: p.ink)),
                  Text('${a.createdByName}${a.storeName != null ? ' · ${a.storeName}' : ''}', style: ts(11, color: p.muted)),
                ],
              ),
            ),
            ListColumn(label: 'Branches', flex: 3, hideOnMobile: true, cell: (c, a) => Text(a.branches.map((b) => b.name).join(', '), style: ts(11, color: p.muted))),
            ListColumn(label: 'Dates', flex: 2, hideOnMobile: true, cell: (c, a) => Text('${a.startsOn} → ${a.endsOn}', style: ts(11, color: p.muted))),
            ListColumn(label: 'Status', flex: 2, cell: (c, a) => StatePill(a.liveState)),
          ],
        ),
      ],
    );
  }
}

/// Live / scheduled / expired / pending / rejected, with an icon.
/// Review status in words.
String reviewStatusLabel(String status) => switch (status) {
      'pending' => 'Waiting for review',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      _ => status,
    };

class StatePill extends StatelessWidget {
  const StatePill(this.state, {super.key});

  final String state;

  @override
  Widget build(BuildContext context) {
    final (label, kind, icon) = switch (state) {
      'live' => ('Live', PillKind.green, Icons.check_circle),
      'scheduled' => ('Scheduled', PillKind.blue, Icons.schedule),
      'expired' => ('Expired', PillKind.off, Icons.history),
      'pending' => ('Waiting for review', PillKind.pending, Icons.hourglass_top),
      'rejected' => ('Rejected', PillKind.off, Icons.cancel_outlined),
      _ => (state, PillKind.off, Icons.circle_outlined),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 12, color: context.pal.muted), const SizedBox(width: 4), Pill(label, kind: kind)],
    );
  }
}
