// A mall (branch) kept on the phone: which package version it has, and what is
// waiting for it: an update offered on mobile data, an update downloaded during
// a trip (switched in when the trip ends), a newer format this app can't read,
// or the server no longer offering it.
import '../../../core/data/shopper_api.dart';

class SavedMall {
  const SavedMall({
    required this.id, required this.name, required this.mallName, required this.package, required this.savedAt,
    this.checkedAt, this.retired = false, this.offered, this.pending, this.newerFormat = false,
  });

  final String id, name, mallName;

  /// The package on the phone.
  final PackageMeta package;
  final DateTime savedAt;

  /// The last time the server was asked about it.
  final DateTime? checkedAt;

  /// The server no longer offers it (switched off, or its map unpublished): kept, "no longer updated".
  final bool retired;

  /// A newer version the server has, waiting for a tap (mobile data).
  final PackageMeta? offered;

  /// A newer version already downloaded, switched in once the trip in this mall ends.
  final PackageMeta? pending;

  /// The server's version is in a format this app can't read: "Update LIQo".
  final bool newerFormat;

  /// The blob key of a version of this mall's package.
  static String key(String id, int version) => 'packages/$id/$version.json';
  String get blobKey => key(id, package.version);

  SavedMall copyWith({String? name, String? mallName, PackageMeta? package, DateTime? savedAt, DateTime? checkedAt, bool? retired, PackageMeta? offered, PackageMeta? pending, bool? newerFormat, bool clearOffered = false, bool clearPending = false}) =>
      SavedMall(
        id: id, name: name ?? this.name, mallName: mallName ?? this.mallName, package: package ?? this.package, savedAt: savedAt ?? this.savedAt,
        checkedAt: checkedAt ?? this.checkedAt, retired: retired ?? this.retired,
        offered: clearOffered ? null : offered ?? this.offered, pending: clearPending ? null : pending ?? this.pending,
        newerFormat: newerFormat ?? this.newerFormat,
      );

  Map<String, Object?> toJson() => {
        'id': id, 'name': name, 'mallName': mallName, 'package': package.toJson(), 'savedAt': savedAt.toIso8601String(),
        if (checkedAt != null) 'checkedAt': checkedAt!.toIso8601String(),
        if (retired) 'retired': true,
        if (offered != null) 'offered': offered!.toJson(),
        if (pending != null) 'pending': pending!.toJson(),
        if (newerFormat) 'newerFormat': true,
      };

  static SavedMall? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final m = j.cast<String, Object?>();
      PackageMeta? meta(Object? x) => x is Map ? PackageMeta.fromJson(x.cast<String, Object?>()) : null;
      return SavedMall(
        id: m['id']!.toString(), name: m['name']?.toString() ?? '', mallName: m['mallName']?.toString() ?? '',
        package: meta(m['package'])!, savedAt: DateTime.parse(m['savedAt']!.toString()),
        checkedAt: m['checkedAt'] == null ? null : DateTime.tryParse(m['checkedAt'].toString()),
        retired: m['retired'] == true, offered: meta(m['offered']), pending: meta(m['pending']), newerFormat: m['newerFormat'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
