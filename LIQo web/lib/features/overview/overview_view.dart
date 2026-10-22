import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/action_label.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import 'overview_service.dart';

class OverviewView extends ConsumerWidget {
  const OverviewView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final user = ref.watch(currentUserProvider);
    final nav = navForRole(user?.role ?? 'store_owner');
    final data = ref.watch(overviewProvider);
    final mobile = Bp.isMobile(context);
    final tablet = Bp.isTablet(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: '${nav.name} / Overview',
          title: nav.title,
          subtitle: nav.subtitle,
          actions: [
            AppButton(
              label: 'Refresh',
              icon: Icons.refresh,
              onPressed: () => ref.invalidate(overviewProvider),
            ),
          ],
        ),
        data.when(
          loading: () => Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GridRows(columns: tablet ? 2 : 5, spacing: mobile ? 10 : 16, children: List.generate(tablet ? 4 : 5, (_) => const SkeletonStatCard())),
                const SizedBox(height: 18),
                const TwoCol(
                  left: SkeletonCard(child: SkeletonLines(widths: [0.8, 0.6, 0.7, 0.5], height: 14, gap: 12)),
                  right: SkeletonCard(child: SkeletonLines(widths: [0.9, 0.5, 0.85, 0.45, 0.7], height: 11, gap: 12)),
                ),
              ],
            ),
          ),
          error: (e, _) => AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Could not load the overview', style: ts(14, w: FontWeight.w700, color: p.ink)),
                const SizedBox(height: 6),
                Text(formatApiError(e), style: ts(12, color: p.muted)),
                const SizedBox(height: 12),
                AppButton(label: 'Try again', primary: true, onPressed: () => ref.invalidate(overviewProvider)),
              ],
            ),
          ),
          data: (d) {
            // Each card opens its page for this role, when the role has one (Round 14).
            String? pathOf(List<String> ids) => nav.items.where((i) => ids.contains(i.id)).firstOrNull?.path;
            VoidCallback? open(List<String> ids) {
              final path = pathOf(ids);
              return path == null ? null : () => context.go(path);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Counts exclude deactivated records, so the labels say "Active".
                GridRows(
                  columns: tablet ? 2 : 5,
                  spacing: mobile ? 10 : 16,
                  children: [
                    _StatCard(label: 'Active malls', value: d.counts.malls, note: 'Registered chains', icon: Icons.storefront_outlined, compact: mobile, onTap: open(['malls'])),
                    _StatCard(label: 'Active branches', value: d.counts.branches, note: 'Physical locations', icon: Icons.location_on_outlined, compact: mobile, onTap: open(['branches', 'branch'])),
                    _StatCard(label: 'Active stores', value: d.counts.stores, note: 'In active branches', icon: Icons.category_outlined, compact: mobile, onTap: open(['stores', 'my_stores'])),
                    _StatCard(
                        label: 'Announcements',
                        value: d.counts.liveAnnouncements,
                        note: '${d.counts.pendingAnnouncements} waiting for review',
                        icon: Icons.campaign_outlined,
                        compact: mobile,
                        onTap: open(['announcements'])),
                    _StatCard(
                        label: 'Map publications',
                        value: d.counts.mapPublications,
                        note: 'Published map versions',
                        icon: Icons.layers_outlined,
                        compact: mobile,
                        onTap: open(['maps', 'map_editor', 'analytics'])),
                  ],
                ),
                const SizedBox(height: 18),
                TwoCol(
                  left: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const CardHead(title: 'Quick actions', subtitle: 'Jump to a page'),
                        CardBody(
                          child: GridRows(
                            columns: 2,
                            spacing: 10,
                            children: [
                              // Up to six pages (Round 14: owners also get Announcements and the Map viewer).
                              for (final item in nav.items.where((i) => i.id != 'overview' && i.id != 'account').take(6)) _QuickTile(item: item, onTap: () => context.go(item.path)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  right: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CardHead(
                          title: 'Recent activity',
                          subtitle: user?.role == 'supervisor' ? 'Your actions and your mall admins\'' : 'Latest recorded actions',
                        ),
                        CardBody(
                          child: d.recent.isEmpty
                              ? Text('Nothing recorded yet.', style: ts(12, color: p.muted))
                              : Column(
                                  children: [
                                    for (var i = 0; i < d.recent.length; i++) ...[
                                      if (i > 0) const SizedBox(height: 14),
                                      _ActivityRow(item: d.recent[i]),
                                    ],
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.compact,
    this.onTap,
  });

  final String label;
  final int value;
  final String note;
  final IconData icon;
  final bool compact;

  /// Opens the page behind the number.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final card = _card(p);
    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: '$label: $value. Open',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: card),
      ),
    );
  }

  Widget _card(Pal p) {
    return AppCard(
      padding: compact ? const EdgeInsets.all(14) : const EdgeInsets.symmetric(horizontal: 19, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: ts(12, color: p.statNote))),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: p.iconBg, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 17, color: p.brand),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text('$value', style: ts(compact ? 24 : 28, w: FontWeight.w800, color: p.ink, ls: -0.8, height: 1.2)),
          ),
          Text(note, style: ts(11, color: p.statNote)),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final RecentActivity item;

  static final _fmt = DateFormat('MMM d, h:mm a');

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = item.action.contains('failed') || item.action.contains('blocked') ? p.warn : p.brand;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Dot(color),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(actionLabel(item.action), style: ts(12, w: FontWeight.w700, color: p.ink)),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('${item.actorEmail ?? 'unknown'} · ${_fmt.format(item.createdAt)}', style: ts(11, color: p.muted)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.item, required this.onTap});

  final NavItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final radius = BorderRadius.circular(11);
    return Material(
      color: p.panel,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: p.line)),
      child: InkWell(
        borderRadius: radius,
        hoverColor: p.quickHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, size: 18, color: p.brand),
              const SizedBox(height: 10),
              Text(item.label, style: ts(12, w: FontWeight.w700, color: p.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
