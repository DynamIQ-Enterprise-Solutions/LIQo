// Home: the board's Categories / Explore screen. The mall in the header, a way
// into search, the category tiles, and the mall's posts as a feed down the
// page, newest first, 10 at a time with "More posts"; offline it keeps the last
// loaded posts and says when they are from; pull down to refresh (owner
// decisions 2026-10-23). Debug builds show the stand-in server's sample posts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/mall_switcher.dart';
import '../../malls/providers/mall_provider.dart';
import '../../malls/views/update_card.dart';
import '../../places/models/category.dart';
import '../../settings/providers/words_provider.dart';
import '../providers/posts_provider.dart';
import 'post_widgets.dart';

class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), mallId = ref.watch(mallProvider);
    final ps = ref.watch(postsProvider), postsN = ref.read(postsProvider.notifier), today = postsN.today();
    final posts = mallId == null ? const [] : ps.visible(today);
    final loc = MaterialLocalizations.of(context);
    return ColoredBox(
      color: p.bg,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: postsN.refresh,
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            const Row(children: [
              BrandWordmark(size: 24),
              SizedBox(width: 12),
              Spacer(),
              Flexible(flex: 4, child: Align(alignment: Alignment.centerRight, child: MallSwitcher())),
            ]),
            const MallUpdateCard(),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: w.tr('Where do you want to go?'),
              excludeSemantics: true,
              onTap: () => context.push('/search'),
              child: InkWell(
                key: const ValueKey('home-search'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/search'),
                child: Ink(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line, width: p.lineW), boxShadow: p.shadow),
                  child: Row(children: [
                    Icon(Icons.search, color: p.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(w.tr('Where do you want to go?'), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, color: p.muted))),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Semantics(header: true, child: Text(w.tr('Categories'), style: ts(20, w: FontWeight.w800, color: p.ink))),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, c) {
              const gap = 10.0, cols = 3;
              final tw = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(spacing: gap, runSpacing: gap, children: [
                for (final cat in categories) SizedBox(width: tw, child: _CategoryTile(cat: cat, label: w.tr(cat.label))),
              ]);
            }),
            if (mallId != null && (posts.isNotEmpty || ps.offline)) ...[
              const SizedBox(height: 22),
              Semantics(header: true, child: Text(w.tr('Posts'), style: ts(20, w: FontWeight.w800, color: p.ink))),
              if (ps.offline && ps.loadedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  w.tr("You're offline · showing posts from ${loc.formatShortMonthDay(ps.loadedAt!)}, ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(ps.loadedAt!))}"),
                  key: const ValueKey('posts-offline'),
                  style: ts(12.5, w: FontWeight.w600, color: p.muted),
                ),
              ],
              const SizedBox(height: 10),
              if (posts.isEmpty) Text(w.tr('No posts right now.'), style: ts(14, color: p.muted)),
              for (final post in posts) ...[PostFeedCard(post: post), const SizedBox(height: 12)],
              if (ps.more(today))
                OutlinedButton(
                  key: const ValueKey('posts-more'),
                  onPressed: ps.loading ? null : postsN.more,
                  child: Text(w.tr('More posts')),
                ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.cat, required this.label});
  final Category cat;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: () => context.go('/home/category/${cat.id}'),
      child: InkWell(
        key: ValueKey('cat-${cat.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/home/category/${cat.id}'),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line, width: p.lineW)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(12)),
              child: Icon(cat.icon, color: p.brand2),
            ),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w700, color: p.ink, height: 1.2)),
          ]),
        ),
      ),
    );
  }
}
