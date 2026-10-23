import '../../core/api_client.dart';
import '../../shared/models/paged.dart';

class AnnouncementBranch {
  const AnnouncementBranch({required this.id, required this.name, required this.mallName});

  final int id;
  final String name;
  final String mallName;

  factory AnnouncementBranch.fromJson(Map<String, dynamic> j) => AnnouncementBranch(id: j['id'] as int, name: j['name'] as String, mallName: j['mallName'] as String? ?? '');

  LookupItem toLookup() => LookupItem(id: id, label: '$mallName · $name');
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.imageUrl,
    required this.startsOn,
    required this.endsOn,
    required this.status,
    required this.liveState,
    this.storeId,
    this.storeName,
    required this.createdBy,
    required this.createdByName,
    required this.createdRole,
    this.reviewedByName,
    this.rejectReason,
    required this.branches,
    required this.createdAt,
    this.sharedBeyondScope = false,
    this.canChange = true,
    this.canDetach = false,
  });

  final int id;
  final String title;
  final String body;
  final String? imageUrl;
  final String startsOn;
  final String endsOn;

  /// pending | approved | rejected
  final String status;

  /// pending | rejected | scheduled | live | expired
  final String liveState;
  final int? storeId;
  final String? storeName;
  final int createdBy;
  final String createdByName;
  final String createdRole;
  final String? reviewedByName;
  final String? rejectReason;

  /// For managers, only their own branches are listed (owner decision 2026-10-22).
  final List<AnnouncementBranch> branches;
  final DateTime createdAt;

  /// It also reaches branches outside the viewer's scope (not listed to them).
  final bool sharedBeyondScope;

  /// The viewer may edit or delete it (author, all targets in scope, or superadmin).
  final bool canChange;

  /// The viewer may only take it off their own branches.
  final bool canDetach;

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'] as int,
        title: j['title'] as String,
        body: j['body'] as String,
        imageUrl: j['imageUrl'] as String?,
        startsOn: j['startsOn'] as String,
        endsOn: j['endsOn'] as String,
        status: j['status'] as String,
        liveState: j['liveState'] as String,
        storeId: j['storeId'] as int?,
        storeName: j['storeName'] as String?,
        createdBy: j['createdBy'] as int,
        createdByName: j['createdByName'] as String? ?? '',
        createdRole: j['createdRole'] as String,
        reviewedByName: j['reviewedByName'] as String?,
        rejectReason: j['rejectReason'] as String?,
        branches: (j['branches'] as List<dynamic>? ?? []).map((e) => AnnouncementBranch.fromJson(e as Map<String, dynamic>)).toList(),
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        sharedBeyondScope: j['sharedBeyondScope'] == true,
        canChange: j['canChange'] != false,
        canDetach: j['canDetach'] == true,
      );
}

class AnnouncementsService {
  AnnouncementsService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<PagedResult<Announcement>> list(ListQuery q) async {
    final r = await _client.dio.get('/announcements', queryParameters: q.toParams());
    return PagedResult.fromJson(r.data as Map<String, dynamic>, Announcement.fromJson);
  }

  Future<Announcement> get(int id) async {
    final r = await _client.dio.get('/announcements/$id');
    return Announcement.fromJson((r.data as Map<String, dynamic>)['announcement'] as Map<String, dynamic>);
  }

  Future<(String, String)> defaults() async {
    final r = await _client.dio.get('/announcements/defaults');
    final d = r.data as Map<String, dynamic>;
    return (d['startsOn'] as String, d['endsOn'] as String);
  }

  Future<Announcement> create(Map<String, Object?> body) async {
    final r = await _client.dio.post('/announcements', data: body);
    return Announcement.fromJson((r.data as Map<String, dynamic>)['announcement'] as Map<String, dynamic>);
  }

  Future<Announcement> update(int id, Map<String, Object?> body) async {
    final r = await _client.dio.put('/announcements/$id', data: body);
    return Announcement.fromJson((r.data as Map<String, dynamic>)['announcement'] as Map<String, dynamic>);
  }

  Future<Announcement> approve(int id) async {
    final r = await _client.dio.post('/announcements/$id/approve', data: {});
    return Announcement.fromJson((r.data as Map<String, dynamic>)['announcement'] as Map<String, dynamic>);
  }

  Future<Announcement> reject(int id, String reason) async {
    final r = await _client.dio.post('/announcements/$id/reject', data: {'reason': reason});
    return Announcement.fromJson((r.data as Map<String, dynamic>)['announcement'] as Map<String, dynamic>);
  }

  /// Deletes it, or, for a shared one the viewer cannot change, takes it off
  /// their branches only. Returns true when it was only taken off their branches.
  Future<bool> delete(int id) async {
    final r = await _client.dio.delete('/announcements/$id');
    return r.statusCode == 200;
  }
}
