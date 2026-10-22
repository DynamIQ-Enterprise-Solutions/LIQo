import '../../core/api_client.dart';
import 'malls_service.dart';

/// An owner of a mall: whole-mall, or only some of its branches.
class MallOwnerRow {
  const MallOwnerRow({required this.id, required this.fullName, required this.email, required this.isActive, required this.wholeMall, required this.branchNames});

  final int id;
  final String fullName;
  final String email;
  final bool isActive;
  final bool wholeMall;
  final String branchNames;

  factory MallOwnerRow.fromJson(Map<String, dynamic> j) => MallOwnerRow(
        id: j['id'] as int,
        fullName: j['fullName'] as String,
        email: j['email'] as String,
        isActive: j['isActive'] as bool? ?? true,
        wholeMall: j['wholeMall'] == true,
        branchNames: j['branchNames'] as String? ?? '',
      );
}

class MallAdminRow {
  const MallAdminRow({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isActive,
    required this.mustChangePassword,
    required this.branches,
    this.reportsToId,
    this.reportsToName,
  });

  final int id;
  final String fullName;
  final String email;
  final bool isActive;
  final bool mustChangePassword;
  final List<({int id, String name})> branches;
  final int? reportsToId;
  final String? reportsToName;

  factory MallAdminRow.fromJson(Map<String, dynamic> j) {
    final rt = j['reportsTo'] as Map<String, dynamic>?;
    return MallAdminRow(
      id: j['id'] as int,
      fullName: j['fullName'] as String,
      email: j['email'] as String,
      isActive: j['isActive'] as bool? ?? true,
      mustChangePassword: j['mustChangePassword'] as bool? ?? false,
      branches: [for (final b in j['branches'] as List<dynamic>) (id: b['id'] as int, name: b['name'] as String)],
      reportsToId: rt?['id'] as int?,
      reportsToName: rt?['name'] as String?,
    );
  }
}

class MallPeople {
  const MallPeople({required this.mall, required this.owners, required this.admins});

  final Mall mall;
  final List<MallOwnerRow> owners;
  final List<MallAdminRow> admins;

  factory MallPeople.fromJson(Map<String, dynamic> j) => MallPeople(
        mall: Mall.fromJson(j['mall'] as Map<String, dynamic>),
        owners: [for (final o in j['owners'] as List<dynamic>) MallOwnerRow.fromJson(o as Map<String, dynamic>)],
        admins: [for (final a in j['admins'] as List<dynamic>) MallAdminRow.fromJson(a as Map<String, dynamic>)],
      );
}

class PeopleService {
  PeopleService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<MallPeople> get(int mallId) async {
    final r = await _client.dio.get('/malls/$mallId/people');
    return MallPeople.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> addOwner(int mallId, int userId) async {
    await _client.dio.post('/malls/$mallId/owners', data: {'userId': userId});
  }

  /// Returns how many admin links were cleared because the owner no longer covers them.
  Future<int> removeOwner(int mallId, int userId) async {
    final r = await _client.dio.delete('/malls/$mallId/owners/$userId');
    return (r.data as Map<String, dynamic>)['linksCleared'] as int? ?? 0;
  }

  /// Sets the admin's branches inside this mall and, when [reportsTo] is given (null clears), their owner.
  /// Places an admin on one branch of the mall; who they report to follows the ownership rule.
  Future<void> setAdmin(int mallId, int userId, {required List<int> branchIds}) async {
    await _client.dio.put('/malls/$mallId/admins/$userId', data: {'branchIds': branchIds});
  }

  Future<void> removeAdmin(int mallId, int userId) async {
    await _client.dio.delete('/malls/$mallId/admins/$userId');
  }
}
