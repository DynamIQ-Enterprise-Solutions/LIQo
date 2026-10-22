// A post's own page: the picture, who wrote it, the title and the text, and a
// note that it is a sample.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/page.dart';
import '../../../shared/widgets/placeholders.dart';
import '../../settings/providers/words_provider.dart';
import '../../places/services/place_info_catalog.dart' show stableHash;
import '../data/sample_posts.dart';
import 'home_view.dart';

class PostView extends ConsumerWidget {
  const PostView({super.key, required this.postId});
  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), post = postById(postId);
    if (post == null) return AppPage(title: w.tr('Post'), children: [Text(w.tr('This post is no longer here.'), style: ts(15, color: p.muted))]);
    return AppPage(
      title: post.title.of(w.lang),
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(borderRadius: BorderRadius.circular(18), child: DrawnArt(motif: post.motif, tone: stableHash(post.id), seed: post.id.length)),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const SampleLabel(),
          Text(authorLabel(post, w), style: ts(13.5, w: FontWeight.w700, color: p.brand2)),
        ]),
        const SizedBox(height: 10),
        Text(post.body.of(w.lang), style: ts(16, color: p.ink, height: 1.5)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 18, color: p.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(w.tr('This is a sample post. Posts from stores, malls and mall management will appear here later.'), style: ts(13, color: p.muted))),
          ]),
        ),
      ],
    );
  }
}
