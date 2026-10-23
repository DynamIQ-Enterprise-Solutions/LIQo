// The current mall's posts (owner decisions 2026-10-23): shown from the phone
// first, then refreshed from the server; 10 at a time with "More posts"; like
// FB/IG offline, the last loaded posts stay with "You're offline · showing posts
// from <time>", and posts past their last day disappear even offline.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/data/blob_store.dart';
import '../../../core/data/net.dart';
import '../../../core/data/shopper_api.dart';
import '../../../core/engine/package/live_info.dart' show phTime;
import '../../malls/providers/mall_provider.dart';
import '../models/post.dart';

@immutable
class PostsState {
  const PostsState({this.branchId, this.items = const [], this.nextCursor, this.loadedAt, this.offline = false, this.loading = false, this.shown = PostsController.page});
  final String? branchId;

  /// Every post loaded (newest first), ended ones included: [visible] leaves those out.
  final List<Post> items;
  final String? nextCursor;

  /// When the posts were last loaded from the server.
  final DateTime? loadedAt;

  /// The last attempt to reach the server failed: the posts are the last loaded ones.
  final bool offline;
  final bool loading;

  /// How many are shown (10, then 10 more per "More posts").
  final int shown;

  /// The posts still on today ([today] in Philippine time), as many as are shown.
  List<Post> visible(DateTime today) => [for (final p in items) if (p.onAt(today)) p].take(shown).toList();

  /// More posts can be shown: loaded ones beyond those shown, or another page on the server.
  bool more(DateTime today) => items.where((p) => p.onAt(today)).length > shown || nextCursor != null;

  PostsState copyWith({List<Post>? items, String? nextCursor, bool clearCursor = false, DateTime? loadedAt, bool? offline, bool? loading, int? shown}) => PostsState(
        branchId: branchId, items: items ?? this.items, nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
        loadedAt: loadedAt ?? this.loadedAt, offline: offline ?? this.offline, loading: loading ?? this.loading, shown: shown ?? this.shown,
      );
}

class PostsController extends Notifier<PostsState> {
  static const page = 10;

  /// The most posts kept on the phone per mall.
  static const keep = 50;

  String? _etag;
  static String _key(String id) => 'posts/$id.json';

  @override
  PostsState build() {
    final id = ref.watch(mallProvider);
    _etag = null;
    if (id != null) Future.microtask(() => _load(id));
    return PostsState(branchId: id);
  }

  BlobStore get _blobs => ref.read(blobStoreProvider);
  DateTime get _now => ref.read(clockProvider)();

  /// Today in Philippine time, for which posts are still on.
  DateTime today() => phTime(_now);

  Future<void> _load(String id) async {
    try {
      final b = await _blobs.read(_key(id));
      if (b != null && state.branchId == id && state.items.isEmpty) {
        final j = (jsonDecode(utf8.decode(b)) as Map).cast<String, Object?>();
        _etag = j['etag']?.toString();
        state = state.copyWith(
          items: [for (final x in j['items'] as List? ?? const []) ?Post.fromJson(x)],
          nextCursor: j['nextCursor']?.toString(),
          loadedAt: DateTime.tryParse(j['loadedAt']?.toString() ?? ''),
        );
      }
    } catch (_) {} // an unreadable copy is replaced by the next refresh
    await refresh();
  }

  void _keep() {
    final id = state.branchId;
    if (id == null) return;
    final body = {'etag': _etag, 'nextCursor': state.nextCursor, 'loadedAt': state.loadedAt?.toIso8601String(), 'items': [for (final p in state.items.take(keep)) p.toJson()]};
    _blobs.write(_key(id), Uint8List.fromList(utf8.encode(jsonEncode(body)))).catchError((_) {});
  }

  /// Loads the newest posts again (pull down, the app opening, the mall changing).
  Future<void> refresh() async {
    final id = state.branchId;
    if (id == null) return;
    if (await ref.read(netProvider).kind() == NetKind.none) {
      state = state.copyWith(offline: true);
      return;
    }
    state = state.copyWith(loading: true);
    try {
      final r = await ref.read(shopperApiProvider).posts(id, etag: _etag);
      if (state.branchId != id) return;
      if (r == null) {
        state = state.copyWith(offline: false, loading: false, loadedAt: _now);
        return;
      }
      final pg = PostsPage.fromJson(r.json);
      _etag = r.etag;
      state = state.copyWith(items: pg.items, nextCursor: pg.nextCursor, clearCursor: pg.nextCursor == null, loadedAt: _now, offline: false, loading: false, shown: page);
      _keep();
    } on Exception {
      if (state.branchId == id) state = state.copyWith(offline: true, loading: false);
    }
  }

  /// "More posts": the next 10, from those loaded or from the server's next page.
  Future<void> more() async {
    final id = state.branchId, today = this.today();
    if (id == null) return;
    final on = state.items.where((p) => p.onAt(today)).length;
    if (on > state.shown || state.nextCursor == null) {
      state = state.copyWith(shown: state.shown + page);
      return;
    }
    state = state.copyWith(loading: true);
    try {
      final r = await ref.read(shopperApiProvider).posts(id, cursor: state.nextCursor);
      if (state.branchId != id || r == null) return;
      final pg = PostsPage.fromJson(r.json), seen = {for (final p in state.items) p.id};
      state = state.copyWith(
        items: [...state.items, for (final p in pg.items) if (!seen.contains(p.id)) p],
        nextCursor: pg.nextCursor, clearCursor: pg.nextCursor == null, shown: state.shown + page, loading: false, offline: false,
      );
      _keep();
    } on Exception {
      if (state.branchId == id) state = state.copyWith(offline: true, loading: false);
    }
  }

  /// A post loaded for the current mall.
  Post? byId(String id) => state.items.where((p) => p.id == id).firstOrNull;
}

final postsProvider = NotifierProvider<PostsController, PostsState>(PostsController.new);
