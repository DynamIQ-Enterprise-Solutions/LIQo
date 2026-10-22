import 'package:flutter/foundation.dart';

import '../../places/models/place_info.dart';

/// Who wrote a post.
enum PostAuthor { mall, store, management }

/// A post on Home. Until posts by stores, malls, mall owners and the superadmin
/// exist (they come later), Home shows clearly labelled samples (owner decision
/// 2026-10-22).
@immutable
class SamplePost {
  const SamplePost({required this.id, required this.mallId, required this.author, required this.authorName, this.placeId, required this.title, required this.body, required this.motif});
  final String id, mallId, authorName;
  final PostAuthor author;

  /// The store a store's post is about.
  final String? placeId;
  final Bilingual title, body;

  /// The drawn picture's motif (a category glyph).
  final String motif;
}
