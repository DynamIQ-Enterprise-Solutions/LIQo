import '../../core/api_client.dart';
import '../../shared/models/paged.dart';

class Store {
  const Store({
    required this.id,
    required this.branchId,
    required this.branchName,
    required this.mallName,
    required this.name,
    this.categoryId,
    this.categoryName,
    this.logoUrl,
    this.description,
    this.openingHours,
    this.contactPhone,
    this.contactEmail,
    required this.isActive,
    required this.spaceCount,
    required this.ownerCount,
  });

  final int id;
  final int branchId;
  final String branchName;
  final String mallName;
  final String name;
  final int? categoryId;
  final String? categoryName;
  final String? logoUrl;
  final String? description;
  final String? openingHours;
  final String? contactPhone;
  final String? contactEmail;
  final bool isActive;
  final int spaceCount;
  final int ownerCount;

  factory Store.fromJson(Map<String, dynamic> j) => Store(
        id: j['id'] as int,
        branchId: j['branchId'] as int,
        branchName: j['branchName'] as String? ?? '',
        mallName: j['mallName'] as String? ?? '',
        name: j['name'] as String,
        categoryId: j['categoryId'] as int?,
        categoryName: j['categoryName'] as String?,
        logoUrl: j['logoUrl'] as String?,
        description: j['description'] as String?,
        openingHours: j['openingHours'] as String?,
        contactPhone: j['contactPhone'] as String?,
        contactEmail: j['contactEmail'] as String?,
        isActive: j['isActive'] as bool? ?? true,
        spaceCount: j['spaceCount'] as int? ?? 0,
        ownerCount: j['ownerCount'] as int? ?? 0,
      );
}

class OwnerRef {
  const OwnerRef({required this.id, required this.email, required this.fullName, required this.isActive});

  final int id;
  final String email;
  final String fullName;
  final bool isActive;

  factory OwnerRef.fromJson(Map<String, dynamic> j) =>
      OwnerRef(id: j['id'] as int, email: j['email'] as String, fullName: j['fullName'] as String, isActive: j['isActive'] as bool? ?? true);
}

class StoreRef {
  const StoreRef({required this.id, required this.name, required this.branchId, required this.branchName, required this.isActive});

  final int id;
  final String name;
  final int branchId;
  final String branchName;
  final bool isActive;

  factory StoreRef.fromJson(Map<String, dynamic> j) => StoreRef(
        id: j['id'] as int,
        name: j['name'] as String,
        branchId: j['branchId'] as int,
        branchName: j['branchName'] as String? ?? '',
        isActive: j['isActive'] as bool? ?? true,
      );
}

class StoreOwner {
  const StoreOwner({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    required this.mustChangePassword,
    this.lastLoginAt,
    required this.stores,
  });

  final int id;
  final String email;
  final String fullName;
  final bool isActive;
  final bool mustChangePassword;
  final DateTime? lastLoginAt;
  final List<StoreRef> stores;

  factory StoreOwner.fromJson(Map<String, dynamic> j) => StoreOwner(
        id: j['id'] as int,
        email: j['email'] as String,
        fullName: j['fullName'] as String,
        isActive: j['isActive'] as bool? ?? true,
        mustChangePassword: j['mustChangePassword'] as bool? ?? false,
        lastLoginAt: j['lastLoginAt'] == null ? null : DateTime.parse(j['lastLoginAt'] as String).toLocal(),
        stores: (j['stores'] as List<dynamic>? ?? []).map((e) => StoreRef.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class BranchOption {
  const BranchOption({required this.id, required this.branchId, required this.kind, required this.name, required this.sortOrder, required this.isActive, required this.inUse});

  final int id;
  final int branchId;
  final String kind;
  final String name;
  final int sortOrder;
  final bool isActive;
  final int inUse;

  factory BranchOption.fromJson(Map<String, dynamic> j) => BranchOption(
        id: j['id'] as int,
        branchId: j['branchId'] as int,
        kind: j['kind'] as String,
        name: j['name'] as String,
        sortOrder: j['sortOrder'] as int? ?? 0,
        isActive: j['isActive'] as bool? ?? true,
        inUse: j['inUse'] as int? ?? 0,
      );
}

const optionKinds = {
  'store_category': 'Store categories',
  'unit_type': 'Unit types',
  'floor_label': 'Floor labels',
};

class StoresService {
  StoresService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Map<String, dynamic> _m(Object? data) => data as Map<String, dynamic>;

  Future<PagedResult<Store>> list(ListQuery q) async {
    final r = await _client.dio.get('/stores', queryParameters: q.toParams());
    return PagedResult.fromJson(_m(r.data), Store.fromJson);
  }

  Future<(Store, List<String>, List<OwnerRef>)> get(int id) async {
    final r = await _client.dio.get('/stores/$id');
    final d = _m(r.data);
    return (
      Store.fromJson(_m(d['store'])),
      (d['spaces'] as List<dynamic>).cast<String>(),
      (d['owners'] as List<dynamic>).map((e) => OwnerRef.fromJson(_m(e))).toList(),
    );
  }

  Future<Store> create(Map<String, Object?> body) async => Store.fromJson(_m(_m((await _client.dio.post('/stores', data: body)).data)['store']));
  Future<Store> update(int id, Map<String, Object?> body) async => Store.fromJson(_m(_m((await _client.dio.put('/stores/$id', data: body)).data)['store']));
  Future<Store> setActive(int id, bool active) async =>
      Store.fromJson(_m(_m((await _client.dio.post('/stores/$id/${active ? 'reactivate' : 'deactivate'}')).data)['store']));

  Future<List<String>> setSpaces(int id, List<String> keys) async =>
      (_m((await _client.dio.put('/stores/$id/spaces', data: {'spaceKeys': keys})).data)['spaces'] as List<dynamic>).cast<String>();

  // ---- Option lists ----

  Future<List<BranchOption>> options(int branchId, {String? kind, bool includeInactive = true}) async {
    final r = await _client.dio.get('/options', queryParameters: {'branchId': branchId, if (kind != null) 'kind': kind, 'includeInactive': '$includeInactive'});
    return (_m(r.data)['items'] as List<dynamic>).map((e) => BranchOption.fromJson(_m(e))).toList();
  }

  Future<BranchOption> createOption(Map<String, Object?> body) async => BranchOption.fromJson(_m(_m((await _client.dio.post('/options', data: body)).data)['option']));
  Future<BranchOption> updateOption(int id, Map<String, Object?> body) async => BranchOption.fromJson(_m(_m((await _client.dio.put('/options/$id', data: body)).data)['option']));
  Future<BranchOption> setOptionActive(int id, bool active) async =>
      BranchOption.fromJson(_m(_m((await _client.dio.post('/options/$id/${active ? 'reactivate' : 'deactivate'}')).data)['option']));
  Future<void> deleteOption(int id) => _client.dio.delete('/options/$id');

  // ---- Store owners ----

  Future<StoreOwner> getOwner(int userId) async => StoreOwner.fromJson(_m(_m((await _client.dio.get('/owners/$userId')).data)['user']));

  Future<BranchOption> getOption(int id) async => BranchOption.fromJson(_m(_m((await _client.dio.get('/options/$id')).data)['option']));

  Future<PagedResult<StoreOwner>> owners(ListQuery q) async {
    final r = await _client.dio.get('/owners', queryParameters: q.toParams());
    return PagedResult.fromJson(_m(r.data), StoreOwner.fromJson);
  }

  /// Returns the owner and, for a brand-new account, the one-time temporary password.
  Future<(StoreOwner, String?)> createOwner({required String email, required String fullName, required int storeId}) async {
    final r = await _client.dio.post('/owners', data: {'email': email, 'fullName': fullName, 'storeId': storeId});
    final d = _m(r.data);
    return (StoreOwner.fromJson(_m(d['user'])), d['tempPassword'] as String?);
  }

  Future<StoreOwner> assignOwner(int userId, int storeId) async =>
      StoreOwner.fromJson(_m(_m((await _client.dio.post('/owners/$userId/assign', data: {'storeId': storeId})).data)['user']));

  Future<(StoreOwner, bool)> unassignOwner(int userId, int storeId) async {
    final d = _m((await _client.dio.post('/owners/$userId/unassign', data: {'storeId': storeId})).data);
    return (StoreOwner.fromJson(_m(d['user'])), d['deactivated'] as bool? ?? false);
  }

  Future<StoreOwner> updateOwner(int userId, {required String email, required String fullName}) async =>
      StoreOwner.fromJson(_m(_m((await _client.dio.put('/owners/$userId', data: {'email': email, 'fullName': fullName})).data)['user']));

  Future<String> resetOwnerPassword(int userId) async => _m((await _client.dio.post('/owners/$userId/reset-password')).data)['tempPassword'] as String;

  Future<StoreOwner> setOwnerActive(int userId, bool active) async =>
      StoreOwner.fromJson(_m(_m((await _client.dio.post('/owners/$userId/${active ? 'reactivate' : 'deactivate'}')).data)['user']));
}
