import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../shared/models/paged.dart';

DateTime? _d(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// A request to change one's own name and email, decided by a superadmin.
class ProfileRequest {
  const ProfileRequest({
    required this.id,
    required this.userId,
    required this.role,
    required this.currentName,
    required this.currentEmail,
    required this.requestedName,
    required this.requestedEmail,
    required this.status,
    this.reason,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final String role;
  final String currentName;
  final String currentEmail;
  final String requestedName;
  final String requestedEmail;

  /// pending, approved, rejected or cancelled.
  final String status;
  final String? reason;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  bool get pending => status == 'pending';
  bool get nameChanged => requestedName != currentName;
  bool get emailChanged => requestedEmail != currentEmail;

  factory ProfileRequest.fromJson(Map<String, dynamic> j) {
    final cur = j['current'] as Map<String, dynamic>;
    final req = j['requested'] as Map<String, dynamic>;
    return ProfileRequest(
      id: j['id'] as int,
      userId: j['userId'] as int,
      role: j['role'] as String? ?? '',
      currentName: cur['fullName'] as String? ?? '',
      currentEmail: cur['email'] as String? ?? '',
      requestedName: req['fullName'] as String? ?? '',
      requestedEmail: req['email'] as String? ?? '',
      status: j['status'] as String,
      reason: j['reason'] as String?,
      reviewedBy: j['reviewedBy'] as String?,
      reviewedAt: _d(j['reviewedAt']),
      createdAt: _d(j['createdAt']) ?? DateTime.now(),
    );
  }
}

/// What the signed-in person owns or manages (GET /profile/access, Round 14).
class MyAccess {
  const MyAccess({required this.role, this.malls = const [], this.branches = const [], this.stores = const [], this.reportsTo});

  final String role;

  /// Mall owners: whole malls. Names only.
  final List<String> malls;

  /// Mall owners: single branches; mall admins: their branch. "Mall · Branch".
  final List<String> branches;

  /// Store owners: "Store · Branch".
  final List<String> stores;

  /// Mall admins: who they report to (null = no owner).
  final String? reportsTo;

  factory MyAccess.fromJson(Map<String, dynamic> j) {
    String label(Map<String, dynamic> x, String name, String parent) => [x[parent], x[name]].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return MyAccess(
      role: j['role'] as String? ?? '',
      malls: [for (final m in (j['malls'] as List? ?? const [])) (m as Map<String, dynamic>)['name'] as String? ?? ''],
      branches: [for (final b in (j['branches'] as List? ?? const [])) label(b as Map<String, dynamic>, 'name', 'mallName')],
      stores: [for (final s in (j['stores'] as List? ?? const [])) label(s as Map<String, dynamic>, 'name', 'branchName')],
      reportsTo: (j['reportsTo'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}

class ProfileService {
  ProfileService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Map<String, dynamic> _m(Object? v) => v as Map<String, dynamic>;

  // ---- Own account ----

  /// Superadmin: change your own details at once.
  Future<AuthUser> updateOwn({required String fullName, required String email}) async {
    final r = await _client.dio.put('/profile', data: {'fullName': fullName, 'email': email});
    return AuthUser.fromJson(_m(_m(r.data)['user']));
  }

  /// My waiting request, else my latest one, else null.
  Future<MyAccess> access() async => MyAccess.fromJson(_m((await _client.dio.get('/profile/access')).data));

  Future<ProfileRequest?> myRequest() async {
    final r = await _client.dio.get('/profile/request');
    final req = _m(r.data)['request'];
    return req == null ? null : ProfileRequest.fromJson(_m(req));
  }

  Future<ProfileRequest> requestChange({required String fullName, required String email}) async {
    final r = await _client.dio.post('/profile/request', data: {'fullName': fullName, 'email': email});
    return ProfileRequest.fromJson(_m(_m(r.data)['request']));
  }

  Future<ProfileRequest> cancel() async {
    final r = await _client.dio.delete('/profile/request');
    return ProfileRequest.fromJson(_m(_m(r.data)['request']));
  }

  // ---- Superadmin review ----

  Future<PagedResult<ProfileRequest>> list(ListQuery q) async {
    final r = await _client.dio.get('/profile-requests', queryParameters: q.toParams());
    return PagedResult.fromJson(_m(r.data), ProfileRequest.fromJson);
  }

  Future<ProfileRequest> get(int id) async => ProfileRequest.fromJson(_m(_m((await _client.dio.get('/profile-requests/$id')).data)['request']));

  Future<ProfileRequest> approve(int id) async => ProfileRequest.fromJson(_m(_m((await _client.dio.post('/profile-requests/$id/approve')).data)['request']));

  Future<ProfileRequest> reject(int id, String reason) async =>
      ProfileRequest.fromJson(_m(_m((await _client.dio.post('/profile-requests/$id/reject', data: {'reason': reason})).data)['request']));

  /// Waiting requests across the platform (the sidebar badge).
  Future<int> pendingCount() async {
    final r = await _client.dio.get('/profile-requests', queryParameters: {'pageSize': 1});
    return _m(r.data)['totalCount'] as int? ?? 0;
  }

  /// The person's waiting request, if any (shown on their account page).
  Future<ProfileRequest?> pendingFor(int userId) async {
    final r = await _client.dio.get('/profile-requests', queryParameters: {'userId': userId, 'pageSize': 1});
    final items = _m(r.data)['items'] as List<dynamic>;
    return items.isEmpty ? null : ProfileRequest.fromJson(_m(items.first));
  }
}

/// Waiting profile requests, for the superadmin's sidebar badge.
/// Invalidate after approving or rejecting.
final myAccessProvider = FutureProvider.autoDispose<MyAccess>((ref) => ProfileService().access());

final pendingProfileRequestsProvider = FutureProvider.autoDispose<int>((ref) => ProfileService().pendingCount());
