import '../../core/api_client.dart';
import '../../shared/models/paged.dart';

class Mall {
  const Mall({required this.id, required this.name, this.logoUrl, required this.isActive, this.branchCount, this.canManage});

  final int id;
  final String name;
  final String? logoUrl;
  final bool isActive;
  final int? branchCount;

  /// From the mall page's read only: whether this person may rename, deactivate or
  /// reactivate it (superadmin, or an owner of the whole mall). Null elsewhere.
  final bool? canManage;

  factory Mall.fromJson(Map<String, dynamic> j) => Mall(
        id: j['id'] as int,
        name: j['name'] as String,
        logoUrl: j['logoUrl'] as String?,
        isActive: j['isActive'] as bool? ?? true,
        branchCount: j['branchCount'] as int?,
      );
}

class Branch {
  const Branch({
    required this.id,
    required this.mallId,
    required this.mallName,
    required this.name,
    this.logoUrl,
    this.address,
    this.latitude,
    this.longitude,
    this.openingHours,
    this.contactPhone,
    this.contactEmail,
    required this.isActive,
  });

  final int id;
  final int mallId;
  final String mallName;
  final String name;
  final String? logoUrl;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? openingHours;
  final String? contactPhone;
  final String? contactEmail;
  final bool isActive;

  factory Branch.fromJson(Map<String, dynamic> j) => Branch(
        id: j['id'] as int,
        mallId: j['mallId'] as int,
        mallName: j['mallName'] as String? ?? '',
        name: j['name'] as String,
        logoUrl: j['logoUrl'] as String?,
        address: j['address'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        openingHours: j['openingHours'] as String?,
        contactPhone: j['contactPhone'] as String?,
        contactEmail: j['contactEmail'] as String?,
        isActive: j['isActive'] as bool? ?? true,
      );
}

/// What deactivating a mall hides. Counts are effective-active only.
class MallImpact {
  const MallImpact({required this.branches, required this.stores, required this.mallAdmins});

  final int branches;
  final int stores;
  final int mallAdmins;

  factory MallImpact.fromJson(Map<String, dynamic> j) => MallImpact(
        branches: j['branches'] as int? ?? 0,
        stores: j['stores'] as int? ?? 0,
        mallAdmins: j['mallAdmins'] as int? ?? 0,
      );
}

/// What deactivating a branch hides.
class BranchImpact {
  const BranchImpact({required this.stores, required this.storeOwners, required this.mallAdmins});

  final int stores;
  final int storeOwners;
  final int mallAdmins;

  factory BranchImpact.fromJson(Map<String, dynamic> j) => BranchImpact(
        stores: j['stores'] as int? ?? 0,
        storeOwners: j['storeOwners'] as int? ?? 0,
        mallAdmins: j['mallAdmins'] as int? ?? 0,
      );
}

class MallsService {
  MallsService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<PagedResult<Mall>> listMalls(ListQuery q) async {
    final r = await _client.dio.get('/malls', queryParameters: q.toParams());
    return PagedResult.fromJson(r.data as Map<String, dynamic>, Mall.fromJson);
  }

  Future<Mall> getMall(int id) async {
    final r = await _client.dio.get('/malls/$id');
    final d = r.data as Map<String, dynamic>;
    final m = Mall.fromJson(d['mall'] as Map<String, dynamic>);
    return Mall(id: m.id, name: m.name, logoUrl: m.logoUrl, isActive: m.isActive, branchCount: m.branchCount, canManage: d['canManage'] as bool? ?? false);
  }

  Future<Mall> createMall(Map<String, Object?> body) async {
    final r = await _client.dio.post('/malls', data: body);
    return Mall.fromJson((r.data as Map<String, dynamic>)['mall'] as Map<String, dynamic>);
  }

  Future<Mall> updateMall(int id, Map<String, Object?> body) async {
    final r = await _client.dio.put('/malls/$id', data: body);
    return Mall.fromJson((r.data as Map<String, dynamic>)['mall'] as Map<String, dynamic>);
  }

  Future<MallImpact> mallImpact(int id) async {
    final r = await _client.dio.get('/malls/$id/impact');
    return MallImpact.fromJson(r.data as Map<String, dynamic>);
  }

  Future<BranchImpact> branchImpact(int id) async {
    final r = await _client.dio.get('/branches/$id/impact');
    return BranchImpact.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Mall> setMallActive(int id, bool active) async {
    final r = await _client.dio.post('/malls/$id/${active ? 'reactivate' : 'deactivate'}');
    return Mall.fromJson((r.data as Map<String, dynamic>)['mall'] as Map<String, dynamic>);
  }

  Future<PagedResult<Branch>> listBranches(ListQuery q) async {
    final r = await _client.dio.get('/branches', queryParameters: q.toParams());
    return PagedResult.fromJson(r.data as Map<String, dynamic>, Branch.fromJson);
  }

  Future<Branch> getBranch(int id) async {
    final r = await _client.dio.get('/branches/$id');
    return Branch.fromJson((r.data as Map<String, dynamic>)['branch'] as Map<String, dynamic>);
  }

  Future<Branch> createBranch(Map<String, Object?> body) async {
    final r = await _client.dio.post('/branches', data: body);
    return Branch.fromJson((r.data as Map<String, dynamic>)['branch'] as Map<String, dynamic>);
  }

  Future<Branch> updateBranch(int id, Map<String, Object?> body) async {
    final r = await _client.dio.put('/branches/$id', data: body);
    return Branch.fromJson((r.data as Map<String, dynamic>)['branch'] as Map<String, dynamic>);
  }

  Future<Branch> setBranchActive(int id, bool active) async {
    final r = await _client.dio.post('/branches/$id/${active ? 'reactivate' : 'deactivate'}');
    return Branch.fromJson((r.data as Map<String, dynamic>)['branch'] as Map<String, dynamic>);
  }
}
