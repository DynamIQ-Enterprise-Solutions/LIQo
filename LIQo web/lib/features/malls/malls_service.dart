import '../../core/api_client.dart';
import '../../shared/models/opening_hours.dart';
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
    this.hours,
    this.mapsLink,
    this.placeName,
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

  /// Round 21: opening hours, and the location from a Google Maps link (the pin's numbers stay hidden).
  final OpeningHours? hours;
  final String? mapsLink;
  final String? placeName;

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
        hours: OpeningHours.fromJson(j['hours']),
        mapsLink: j['mapsLink'] as String?,
        placeName: j['placeName'] as String?,
      );
}

/// A lift, escalator, stairs, ramp or walkway on the published map, and whether it is out of service (Round 21).
class MapConnector {
  const MapConnector({required this.id, required this.kind, this.name, this.levels = const [], required this.outOfService, this.since, this.markedByName});

  final String id;
  final String kind;
  final String? name;
  final List<String> levels;
  final bool outOfService;
  final DateTime? since;
  final String? markedByName;

  factory MapConnector.fromJson(Map<String, dynamic> j) => MapConnector(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'stairs',
        name: j['name'] as String?,
        levels: [for (final l in (j['levels'] as List? ?? const [])) l.toString()],
        outOfService: j['outOfService'] == true,
        since: DateTime.tryParse(j['since']?.toString() ?? '')?.toLocal(),
        markedByName: j['markedByName'] as String?,
      );

  String get kindLabel => const {
        'elevator': 'Lift',
        'escalator': 'Escalator',
        'stairs': 'Stairs',
        'ramp': 'Ramp',
        'moving_walkway': 'Moving walkway',
        'walkway': 'Walkway',
        'bridge': 'Bridge',
      }[kind] ??
      kind;
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

  Future<Branch> setBranchHours(int id, OpeningHours? hours) async =>
      Branch.fromJson(((await _client.dio.put('/branches/$id/hours', data: {'hours': hours?.toJson()})).data as Map<String, dynamic>)['branch'] as Map<String, dynamic>);

  /// Reads a pasted Google Maps link without saving it: the place name to confirm (may be null).
  Future<String?> checkLocation(int id, String link) async =>
      ((await _client.dio.post('/branches/$id/location/check', data: {'mapsLink': link})).data as Map<String, dynamic>)['placeName'] as String?;

  Future<Branch> setLocation(int id, String? link) async =>
      Branch.fromJson(((await _client.dio.put('/branches/$id/location', data: {'mapsLink': link})).data as Map<String, dynamic>)['branch'] as Map<String, dynamic>);

  /// The published map's lifts, escalators and stairs; [published] is false when the branch has no published map.
  Future<({bool published, List<MapConnector> items})> connectors(int branchId) async {
    final d = (await _client.dio.get('/maps/$branchId/connectors')).data as Map<String, dynamic>;
    return (published: d['published'] == true, items: [for (final c in d['items'] as List) MapConnector.fromJson(c as Map<String, dynamic>)]);
  }

  Future<List<MapConnector>> setOutOfService(int branchId, String connectorId, bool out) async {
    final d = (await _client.dio.put('/maps/$branchId/connectors/$connectorId/out-of-service', data: {'out': out})).data as Map<String, dynamic>;
    return [for (final c in d['items'] as List) MapConnector.fromJson(c as Map<String, dynamic>)];
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
