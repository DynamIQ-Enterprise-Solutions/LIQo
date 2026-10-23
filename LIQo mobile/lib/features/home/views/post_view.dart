// A post's own page: the picture, who posted it, the title, the full text and
// its dates; a store's post has Directions to that store and a link to its
// place page (owner decision 2026-10-23); the heart and Comment wait for
// accounts. Sample posts (debug builds) say so.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/engine/package/package_venue.dart';
import '../../../core/engine/venue.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/page.dart';
import '../../malls/providers/mall_provider.dart';
import '../../navigation/providers/nav_provider.dart';
import '../../settings/providers/words_provider.dart';
import '../models/post.dart';
import '../providers/posts_provider.dart';
import 'post_widgets.dart';

/// The place a store's post is about, in the current mall: by its store id (a published mall),
/// or the sample's own place id.
Place? postPlace(Venue? v, Post post) {
  if (v == null || !post.byStore) return null;
  if (post.placeId != null) return v.placeById(post.placeId!);
  final sid = post.storeId;
  if (sid == null || v is! PackageVenue) return null;
  final pid = v.storeOf.entries.where((e) => e.value == sid).map((e) => e.key).firstOrNull;
  return pid == null ? null : v.placeById(pid);
}

class PostView extends ConsumerWidget {
  const PostView({super.key, required this.postId});
  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(postsProvider);
    final p = context.pal, w = ref.watch(wordsProvider), post = ref.read(postsProvider.notifier).byId(postId);
    if (post == null) return AppPage(title: w.tr('Post'), children: [Text(w.tr('This post is no longer here.'), style: ts(15, color: p.muted))]);
    final mallId = ref.watch(mallProvider), place = postPlace(ref.watch(currentVenueProvider), post), until = postUntil(context, post, w);
    return AppPage(
      title: post.titleIn(w.lang),
      children: [
        AspectRatio(aspectRatio: 16 / 9, child: ClipRRect(borderRadius: BorderRadius.circular(18), child: PostPicture(post: post))),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (post.sample) const SampleLabel(),
          Text(postAuthorLabel(post, w), style: ts(13.5, w: FontWeight.w700, color: p.brand2)),
          if (until != null) Text(until, style: ts(13, color: p.muted)),
        ]),
        const SizedBox(height: 10),
        Text(post.bodyIn(w.lang), style: ts(16, color: p.ink, height: 1.5)),
        if (place != null) ...[
          const SizedBox(height: 16),
          PrimaryButton(
            key: const ValueKey('post-directions'),
            label: w.tr('Directions'),
            icon: Icons.directions,
            onPressed: () {
              ref.read(navProvider.notifier).startTo(place.id);
              context.go('/map');
            },
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              key: const ValueKey('post-store'),
              onPressed: () => context.push('/place/$mallId/${place.id}'),
              child: Text(w.tr('See ${place.name}')),
            ),
          ),
        ],
        const SizedBox(height: 6),
        PostActions(post: post),
        if (post.sample) ...[
          const SizedBox(height: 12),
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
      ],
    );
  }
}
