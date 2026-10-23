// A post in the feed and on its page (owner decisions 2026-10-23): the picture
// (or the drawn placeholder), who posted it, the title, the text and its last
// day, and a heart and Comment that wait for accounts ("Sign in to react and
// comment · Accounts are coming soon"; sign-in stays optional).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/words.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/placeholders.dart';
import '../../../shared/widgets/toast.dart';
import '../../places/services/place_info_catalog.dart' show stableHash;
import '../../settings/providers/words_provider.dart';
import '../models/post.dart';

/// "Uniqlo · Store" / "SM North EDSA · Mall".
String postAuthorLabel(Post p, Words w) => '${p.authorName} · ${w.tr(p.byStore ? 'Store' : 'Mall')}';

/// "Until Oct 26" (nothing for the samples, which have no real end).
String? postUntil(BuildContext context, Post p, Words w) =>
    p.sample ? null : w.tr('Until ${MaterialLocalizations.of(context).formatShortMonthDay(p.endsOn)}');

/// The post's picture, or the drawn art while it isn't on the phone.
class PostPicture extends StatelessWidget {
  const PostPicture({super.key, required this.post});
  final Post post;
  @override
  Widget build(BuildContext context) {
    final art = DrawnArt(motif: post.motif ?? (post.byStore ? 'other' : 'garden'), tone: stableHash(post.id), seed: post.id.length);
    return CachedPicture(url: post.imageUrl, fallback: art);
  }
}

/// "Sign in to react and comment · Accounts are coming soon".
void accountsSoon(BuildContext context, WidgetRef ref) => showToast(context, ref.read(wordsProvider).tr('Sign in to react and comment · Accounts are coming soon'));

/// The heart and Comment buttons (they wait for accounts).
class PostActions extends ConsumerWidget {
  const PostActions({super.key, required this.post});
  final Post post;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    Widget b(String key, IconData icon, String label) => TextButton.icon(
          key: ValueKey('$key-${post.id}'),
          onPressed: () => accountsSoon(context, ref),
          icon: Icon(icon, size: 20, color: p.muted),
          label: Text(label, style: ts(13.5, w: FontWeight.w700, color: p.muted)),
        );
    return Wrap(spacing: 4, children: [b('post-heart', Icons.favorite_border, w.tr('Heart')), b('post-comment', Icons.mode_comment_outlined, w.tr('Comment'))]);
  }
}

/// One post in Home's feed.
class PostFeedCard extends ConsumerWidget {
  const PostFeedCard({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), until = postUntil(context, post, w);
    return Container(
      decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line, width: p.lineW), boxShadow: p.shadow),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          label: '${post.sample ? '${w.tr('Sample post')}. ' : ''}${post.titleIn(w.lang)}. ${postAuthorLabel(post, w)}',
          excludeSemantics: true,
          onTap: () => context.push('/post/${post.id}'),
          child: InkWell(
            key: ValueKey('post-${post.id}'),
            onTap: () => context.push('/post/${post.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AspectRatio(
                aspectRatio: 16 / 7,
                child: Stack(fit: StackFit.expand, children: [
                  PostPicture(post: post),
                  if (post.sample) const Positioned(left: 10, top: 10, child: SampleLabel()),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(postAuthorLabel(post, w), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: p.brand2)),
                  const SizedBox(height: 2),
                  Text(post.titleIn(w.lang), maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(16, w: FontWeight.w800, color: p.ink, height: 1.25)),
                  const SizedBox(height: 4),
                  Text(post.bodyIn(w.lang), maxLines: 3, overflow: TextOverflow.ellipsis, style: ts(13.5, color: p.muted)),
                  if (until != null) ...[
                    const SizedBox(height: 4),
                    Text(until, style: ts(12.5, w: FontWeight.w600, color: p.muted)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 2), child: PostActions(post: post)),
      ]),
    );
  }
}

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
