// Home: the board's Categories / Explore screen. The mall in the header, a way
// into search, the category tiles, and the posts carousel. Until posts by
// stores, malls, mall owners and the superadmin exist, the carousel shows five
// clearly labelled sample posts per mall (owner decisions 2026-10-22).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/words.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/mall_switcher.dart';
import '../../../shared/widgets/placeholders.dart';
import '../../malls/providers/mall_provider.dart';
import '../../places/models/category.dart';
import '../../places/services/place_info_catalog.dart' show stableHash;
import '../../settings/providers/words_provider.dart';
import '../data/sample_posts.dart';
import '../models/sample_post.dart';

class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), mallId = ref.watch(mallProvider);
    final posts = mallId == null ? const <SamplePost>[] : postsFor(mallId);
    return ColoredBox(
      color: p.bg,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            const Row(children: [
              BrandWordmark(size: 24),
              SizedBox(width: 12),
              Spacer(),
              Flexible(flex: 4, child: Align(alignment: Alignment.centerRight, child: MallSwitcher())),
            ]),
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
            if (posts.isNotEmpty) ...[
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: Semantics(header: true, child: Text(w.tr('Posts'), style: ts(20, w: FontWeight.w800, color: p.ink)))),
                const SampleLabel(),
              ]),
              const SizedBox(height: 10),
              _PostsCarousel(posts: posts, w: w),
            ],
          ],
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

/// The posts, swiping sideways.
class _PostsCarousel extends StatelessWidget {
  const _PostsCarousel({required this.posts, required this.w});
  final List<SamplePost> posts;
  final Words w;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final height = 120 + 132 * scale;
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, c) {
        final cardW = (c.maxWidth * .84).clamp(200.0, 420.0);
        return ListView.separated(
          key: const ValueKey('posts'),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: posts.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) => SizedBox(width: cardW, child: PostCard(post: posts[i], w: w)),
        );
      }),
    );
  }
}

/// One post's card: the picture, who wrote it, the title and the start of the text.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, required this.w});
  final SamplePost post;
  final Words w;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      label: '${w.tr('Sample post')}. ${post.title.of(w.lang)}. ${authorLabel(post, w)}',
      excludeSemantics: true,
      onTap: () => context.push('/post/${post.id}'),
      child: InkWell(
        key: ValueKey('post-${post.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/post/${post.id}'),
        child: Ink(
          decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line, width: p.lineW), boxShadow: p.shadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 110,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                child: Stack(fit: StackFit.expand, children: [
                  DrawnArt(motif: post.motif, tone: stableHash(post.id), seed: post.id.length),
                  const Positioned(left: 10, top: 10, child: SampleLabel()),
                ]),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(authorLabel(post, w), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: p.brand2)),
                  const SizedBox(height: 2),
                  Text(post.title.of(w.lang), maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(16, w: FontWeight.w800, color: p.ink, height: 1.25)),
                  const SizedBox(height: 4),
                  Expanded(child: Text(post.body.of(w.lang), maxLines: 3, overflow: TextOverflow.ellipsis, style: ts(13, color: p.muted))),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Bayview Grand · Mall" / "FreshMart · Store" / "Meridian Management · Mall management".
String authorLabel(SamplePost post, Words w) => '${post.authorName} · ${w.tr(switch (post.author) {
      PostAuthor.mall => 'Mall',
      PostAuthor.store => 'Store',
      PostAuthor.management => 'Mall management',
    })}';

/// The "Sample" label on made-up content.
class SampleLabel extends ConsumerWidget {
  const SampleLabel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: p.soonBg, borderRadius: BorderRadius.circular(999), border: Border.all(color: p.soon.withValues(alpha: .4))),
      child: Text(w.tr('Sample'), style: ts(11, w: FontWeight.w800, color: p.soon, ls: .4)),
    );
  }
}
