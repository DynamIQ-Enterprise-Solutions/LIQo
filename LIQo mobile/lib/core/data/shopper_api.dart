// The shopper server as the app sees it (docs/shopper-hybrid-decisions.md §3):
// the LIQo directory, each branch's package and the app's config. The real one
// talks HTTP to the address set at build time; debug builds and tests use the
// stand-in that serves the sample malls (features/malls/data/sample_server.dart).
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// No connection, or the server could not be reached.
class OfflineException implements Exception {
  const OfflineException([this.cause]);
  final Object? cause;
  @override
  String toString() => 'OfflineException($cause)';
}

/// The server answered, but not with what was asked for.
class ServerException implements Exception {
  const ServerException(this.status, [this.message = '']);
  final int status;
  final String message;
  @override
  String toString() => 'ServerException($status $message)';
}

/// A published package: its version, format, checksum (SHA-256 of the bytes) and size.
class PackageMeta {
  const PackageMeta({required this.version, required this.formatVersion, required this.checksum, required this.sizeBytes});
  final int version, formatVersion, sizeBytes;
  final String checksum;

  factory PackageMeta.fromJson(Map<String, Object?> j) => PackageMeta(
        version: (j['version']! as num).toInt(),
        formatVersion: (j['formatVersion']! as num).toInt(),
        checksum: j['checksum']!.toString(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      );
  Map<String, Object?> toJson() => {'version': version, 'formatVersion': formatVersion, 'checksum': checksum, 'sizeBytes': sizeBytes};
}

/// One branch in the directory. [package] is null while it has no published map.
class BranchEntry {
  const BranchEntry({required this.id, required this.name, required this.mallId, required this.mallName, this.address = '', this.lat, this.lng, this.active = true, this.package});
  final String id, name, mallId, mallName, address;
  final double? lat, lng;
  final bool active;
  final PackageMeta? package;

  /// Offered for download: active and published.
  bool get offered => active && package != null;

  factory BranchEntry.fromJson(Map<String, Object?> j) => BranchEntry(
        id: j['id']!.toString(),
        name: j['name']?.toString() ?? '',
        mallId: j['mallId']?.toString() ?? '',
        mallName: j['mallName']?.toString() ?? '',
        address: j['address']?.toString() ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        active: j['active'] != false,
        package: j['package'] is Map ? PackageMeta.fromJson((j['package']! as Map).cast<String, Object?>()) : null,
      );
  Map<String, Object?> toJson() => {
        'id': id, 'name': name, 'mallId': mallId, 'mallName': mallName, 'address': address,
        if (lat != null) 'lat': lat, if (lng != null) 'lng': lng, 'active': active,
        if (package != null) 'package': package!.toJson(),
      };
}

class DirectoryData {
  const DirectoryData(this.branches);
  final List<BranchEntry> branches;

  BranchEntry? branch(String id) => branches.where((b) => b.id == id).firstOrNull;

  factory DirectoryData.fromJson(Map<String, Object?> j) =>
      DirectoryData([for (final b in (j['branches'] as List? ?? const [])) BranchEntry.fromJson((b as Map).cast<String, Object?>())]);
  Map<String, Object?> toJson() => {'branches': [for (final b in branches) b.toJson()]};
}

/// What the server says about app versions: below [mustUpdateBelow] the app must be updated.
class AppConfig {
  const AppConfig({this.minAppVersion, this.mustUpdateBelow, this.serverTime});
  final String? minAppVersion, mustUpdateBelow;
  final DateTime? serverTime;

  factory AppConfig.fromJson(Map<String, Object?> j) => AppConfig(
        minAppVersion: j['minAppVersion']?.toString(),
        mustUpdateBelow: j['mustUpdateBelow']?.toString(),
        serverTime: j['serverTime'] == null ? null : DateTime.tryParse(j['serverTime'].toString()),
      );
}

abstract class ShopperApi {
  /// Every branch, with its published package's metadata.
  Future<DirectoryData> directory();

  /// A branch's package, as bytes (checked against the directory's checksum by the caller).
  Future<Uint8List> package(String branchId, int version);

  Future<AppConfig> appConfig();

  /// A branch's live store info (docs/shopper-package-format.md §7), or null when it hasn't
  /// changed since [etag].
  Future<({Map<String, Object?> json, String? etag})?> live(String branchId, {String? etag});

  /// A page of a branch's posts (§8), newest first; null when the first page hasn't changed since [etag].
  Future<({Map<String, Object?> json, String? etag})?> posts(String branchId, {String? cursor, String? etag});
}

/// SHA-256 of [bytes], as lowercase hex (the package checksum).
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// The real server, at [base] (e.g. https://api.example.com). With no address set every
/// call fails as offline, so a release built without one simply waits for a connection.
class HttpShopperApi implements ShopperApi {
  HttpShopperApi(this.base, [http.Client? client]) : _client = client ?? http.Client();
  final String base;
  final http.Client _client;
  static const _timeout = Duration(seconds: 20);

  Future<http.Response> _get(String path, {Map<String, String>? headers, bool allow304 = false}) async {
    if (base.isEmpty) throw const OfflineException('no server address');
    try {
      final r = await _client.get(Uri.parse('$base/api/shopper$path'), headers: headers).timeout(_timeout);
      if (r.statusCode != 200 && !(allow304 && r.statusCode == 304)) throw ServerException(r.statusCode, r.reasonPhrase ?? '');
      return r;
    } on ServerException {
      rethrow;
    } catch (e) {
      throw OfflineException(e);
    }
  }

  Map<String, Object?> _json(http.Response r) => (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, Object?>();

  @override
  Future<DirectoryData> directory() async => DirectoryData.fromJson(_json(await _get('/directory')));

  @override
  Future<Uint8List> package(String branchId, int version) async => (await _get('/branches/$branchId/package?version=$version')).bodyBytes;

  @override
  Future<AppConfig> appConfig() async => AppConfig.fromJson(_json(await _get('/app-config')));

  @override
  Future<({Map<String, Object?> json, String? etag})?> live(String branchId, {String? etag}) async {
    final r = await _get('/branches/$branchId/live', headers: {'If-None-Match': ?etag}, allow304: true);
    if (r.statusCode == 304) return null;
    return (json: _json(r), etag: r.headers['etag']);
  }

  @override
  Future<({Map<String, Object?> json, String? etag})?> posts(String branchId, {String? cursor, String? etag}) async {
    final q = 'branch=${Uri.encodeQueryComponent(branchId)}${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}';
    final r = await _get('/posts?$q', headers: {'If-None-Match': ?(cursor == null ? etag : null)}, allow304: true);
    if (r.statusCode == 304) return null;
    return (json: _json(r), etag: r.headers['etag']);
  }
}

/// The server address, set at build time: --dart-define=SHOPPER_API=https://...
const shopperApiBase = String.fromEnvironment('SHOPPER_API');

/// The server; main() picks the real one or the stand-in, tests override it.
final shopperApiProvider = Provider<ShopperApi>((ref) => HttpShopperApi(shopperApiBase));
