// A post on Home: an approved announcement from the shopper server
// (docs/shopper-package-format.md §8). Text shows as written. The stand-in
// server's sample posts also carry a Tagalog text, a place id (they have no
// store ids) and a drawn picture's motif, and are labelled "Sample".
import 'package:flutter/foundation.dart';

@immutable
class Post {
  const Post({
    required this.id, required this.title, required this.body, required this.authorKind, required this.authorName,
    required this.startsOn, required this.endsOn, required this.branchId, this.branchName = '', this.mallName = '',
    this.imageUrl, this.storeId, this.placeId, this.titleTl, this.bodyTl, this.motif, this.sample = false,
  });

  final String id, title, body, authorName, branchId, branchName, mallName;

  /// store | mall
  final String authorKind;

  /// Philippine dates; [endsOn] is the last day shown.
  final DateTime startsOn, endsOn;
  final String? imageUrl, storeId;

  /// Sample posts only: the place a store's post is about, the Tagalog text, the drawn picture.
  final String? placeId, titleTl, bodyTl, motif;
  final bool sample;

  bool get byStore => authorKind == 'store';

  String titleIn(String lang) => lang == 'tl' && titleTl != null ? titleTl! : title;
  String bodyIn(String lang) => lang == 'tl' && bodyTl != null ? bodyTl! : body;

  /// Still on: its last day hasn't passed ([today] is a Philippine date).
  bool onAt(DateTime today) => !DateTime(endsOn.year, endsOn.month, endsOn.day).isBefore(DateTime(today.year, today.month, today.day));

  static DateTime _day(Object? v) {
    final p = v.toString().split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Post? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final a = (j['author'] as Map?) ?? const {}, b = (j['branch'] as Map?) ?? const {};
      return Post(
        id: j['id'].toString(),
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        imageUrl: j['imageUrl']?.toString(),
        authorKind: a['kind']?.toString() == 'store' ? 'store' : 'mall',
        authorName: a['name']?.toString() ?? '',
        storeId: a['storeId']?.toString(),
        startsOn: _day(j['startsOn']),
        endsOn: _day(j['endsOn']),
        branchId: b['id']?.toString() ?? '',
        branchName: b['name']?.toString() ?? '',
        mallName: b['mallName']?.toString() ?? '',
        placeId: j['placeId']?.toString(),
        titleTl: j['titleTl']?.toString(),
        bodyTl: j['bodyTl']?.toString(),
        motif: j['motif']?.toString(),
        sample: j['sample'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
        'id': id, 'title': title, 'body': body, 'imageUrl': ?imageUrl,
        'author': {'kind': authorKind, 'name': authorName, 'storeId': ?storeId},
        'startsOn': _ymd(startsOn), 'endsOn': _ymd(endsOn),
        'branch': {'id': branchId, 'name': branchName, 'mallName': mallName},
        'placeId': ?placeId, 'titleTl': ?titleTl, 'bodyTl': ?bodyTl, 'motif': ?motif, if (sample) 'sample': true,
      };
}

/// A page of posts from the server.
class PostsPage {
  const PostsPage(this.items, this.nextCursor);
  final List<Post> items;
  final String? nextCursor;

  factory PostsPage.fromJson(Map j) =>
      PostsPage([for (final x in j['items'] as List? ?? const []) ?Post.fromJson(x)], j['nextCursor']?.toString());
}
