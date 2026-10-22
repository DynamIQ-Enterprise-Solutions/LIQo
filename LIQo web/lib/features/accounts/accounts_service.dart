import '../../core/api_client.dart';
import '../../shared/models/paged.dart';

/// Assignment counts shown in the accounts list. Whole malls apply to
/// supervisors, branches to supervisors and mall admins, stores to owners.
class AccountAccess {
  const AccountAccess({this.malls = 0, this.branches = 0, this.stores = 0});

  final int malls;
  final int branches;
  final int stores;

  bool get isEmpty => malls == 0 && branches == 0 && stores == 0;

  factory AccountAccess.fromJson(Map<String, dynamic> j) => AccountAccess(
        malls: j['malls'] as int? ?? 0,
        branches: j['branches'] as int? ?? 0,
        stores: j['stores'] as int? ?? 0,
      );
}

class Account {
  const Account({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.mustChangePassword,
    this.lastLoginAt,
    this.createdAt,
    this.access,
    this.reportsTo,
    this.lockedUntil,
  });

  /// Set while a lockout is active (ISO date-time), else null.
  final String? lockedUntil;

  final int id;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;
  final bool mustChangePassword;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;

  /// Present on list rows only.
  final AccountAccess? access;

  /// Mall admins: the owner they report to, if any.
  final ReportsTo? reportsTo;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as int,
        email: j['email'] as String,
        fullName: j['fullName'] as String,
        role: j['role'] as String,
        isActive: j['isActive'] as bool? ?? true,
        mustChangePassword: j['mustChangePassword'] as bool? ?? false,
        lastLoginAt: j['lastLoginAt'] == null ? null : DateTime.parse(j['lastLoginAt'] as String).toLocal(),
        createdAt: j['createdAt'] == null ? null : DateTime.parse(j['createdAt'] as String).toLocal(),
        access: j['access'] == null ? null : AccountAccess.fromJson(j['access'] as Map<String, dynamic>),
        reportsTo: j['reportsTo'] == null ? null : ReportsTo.fromJson(j['reportsTo'] as Map<String, dynamic>),
        lockedUntil: j['lockedUntil'] as String?,
      );
}

class ReportsTo {
  const ReportsTo({required this.id, required this.name});

  final int id;
  final String name;

  factory ReportsTo.fromJson(Map<String, dynamic> j) => ReportsTo(id: j['id'] as int, name: j['name'] as String? ?? '');
}

const roleLabels = {
  'superadmin': 'Superadmin',
  'supervisor': 'Mall Owner',
  'mall_admin': 'Mall Admin',
  'store_owner': 'Store Owner',
};

/// A branch an account is assigned to. The mall is known for mall admins;
/// supervisor rows carry the mall name inside the label only.
class AssignedBranch {
  const AssignedBranch({required this.id, required this.name, this.mallId, this.mallName = ''});

  final int id;
  final String name;
  final int? mallId;
  final String mallName;

  String get label => mallName.isEmpty ? name : '$mallName · $name';
}

class AccountAssignments {
  const AccountAssignments({this.malls = const [], this.branches = const []});

  final List<LookupItem> malls;
  final List<AssignedBranch> branches;

  factory AccountAssignments.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const AccountAssignments();
    return AccountAssignments(
      malls: [for (final m in (j['malls'] as List<dynamic>? ?? [])) LookupItem(id: m['id'] as int, label: m['name'] as String)],
      branches: [
        for (final b in (j['branches'] as List<dynamic>? ?? []))
          AssignedBranch(
            id: b['id'] as int,
            name: b['name'] as String,
            mallId: b['mallId'] as int?,
            mallName: b['mallName'] as String? ?? '',
          ),
      ],
    );
  }
}

class AccountsService {
  AccountsService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<PagedResult<Account>> list(ListQuery q) async {
    final r = await _client.dio.get('/accounts', queryParameters: q.toParams());
    return PagedResult.fromJson(r.data as Map<String, dynamic>, Account.fromJson);
  }

  Future<(Account, AccountAssignments)> get(int id) async {
    final r = await _client.dio.get('/accounts/$id');
    final data = r.data as Map<String, dynamic>;
    return (
      Account.fromJson(data['user'] as Map<String, dynamic>),
      AccountAssignments.fromJson(data['assignments'] as Map<String, dynamic>?),
    );
  }

  /// Creates the account and its first assignment in one request.
  /// Returns the account and its one-time temporary password.
  Future<(Account, String)> create({
    required String email,
    required String fullName,
    required String role,
    List<int> mallIds = const [],
    List<int> branchIds = const [],
  }) async {
    final r = await _client.dio.post('/accounts', data: {
      'email': email,
      'fullName': fullName,
      'role': role,
      if (mallIds.isNotEmpty || branchIds.isNotEmpty) 'assignments': {'mallIds': mallIds, 'branchIds': branchIds},
    });
    final data = r.data as Map<String, dynamic>;
    return (Account.fromJson(data['user'] as Map<String, dynamic>), data['tempPassword'] as String);
  }

  Future<Account> update(int id, {required String email, required String fullName}) async {
    final r = await _client.dio.put('/accounts/$id', data: {'email': email, 'fullName': fullName});
    return Account.fromJson((r.data as Map<String, dynamic>)['user'] as Map<String, dynamic>);
  }

  Future<Account> setActive(int id, bool active) async {
    final r = await _client.dio.post('/accounts/$id/${active ? 'reactivate' : 'deactivate'}');
    return Account.fromJson((r.data as Map<String, dynamic>)['user'] as Map<String, dynamic>);
  }

  Future<String> resetPassword(int id) async {
    final r = await _client.dio.post('/accounts/$id/reset-password');
    return (r.data as Map<String, dynamic>)['tempPassword'] as String;
  }



  Future<void> setSupervisorAssignments(int userId, {required List<int> mallIds, required List<int> branchIds}) async {
    await _client.dio.put('/assignments/supervisors/$userId', data: {'mallIds': mallIds, 'branchIds': branchIds});
  }

  Future<void> setMallAdminAssignments(int userId, {required List<int> branchIds}) async {
    await _client.dio.put('/assignments/mall-admins/$userId', data: {'branchIds': branchIds});
  }
}
