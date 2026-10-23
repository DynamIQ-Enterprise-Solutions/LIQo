// The stand-in shopper server: serves the three sample malls as packages, the
// way the real server will serve published maps. Debug builds without a server
// address use it, and tests; release builds never show the samples (owner
// decision 2026-10-23).
import 'dart:convert';
import 'dart:typed_data';

import '../../../core/data/shopper_api.dart';
import '../../../core/engine/kit/kit_venue.dart';
import '../../../core/engine/package/package_export.dart';
import '../../../core/engine/package/package_venue.dart';
import '../../home/data/sample_posts.dart';
import '../../home/models/sample_post.dart';
import '../models/saved_mall.dart';
import 'registry.dart';

/// The sample malls' group in the directory.
const sampleMallId = 'samples', sampleMallName = 'LIQo sample malls';

final _bytes = <String, Uint8List>{};
final _venues = <String, KitVenue>{};

KitVenue _venue(String id) => _venues[id] ??= venueRegistry.firstWhere((e) => e.id == id).build() as KitVenue;

/// A sample mall's package bytes, built once per run.
Uint8List samplePackageBytes(String id) => _bytes[id] ??= Uint8List.fromList(utf8.encode(jsonEncode(exportPackage(_venue(id)))));

PackageMeta sampleMeta(String id) {
  final b = samplePackageBytes(id);
  return PackageMeta(version: 1, formatVersion: packageFormatVersion, checksum: sha256Hex(b), sizeBytes: b.length);
}

BranchEntry sampleBranch(String id) {
  final v = _venue(id);
  return BranchEntry(id: id, name: v.name, mallId: sampleMallId, mallName: sampleMallName, address: v.tagline, package: sampleMeta(id));
}

class SampleShopperApi implements ShopperApi {
  /// Calls made, for tests.
  final calls = <String>[];

  @override
  Future<DirectoryData> directory() async {
    calls.add('directory');
    return DirectoryData([for (final e in venueRegistry) sampleBranch(e.id)]);
  }

  @override
  Future<Uint8List> package(String branchId, int version) async {
    calls.add('package:$branchId');
    if (!venueRegistry.any((e) => e.id == branchId)) throw const ServerException(404, 'No such branch');
    return samplePackageBytes(branchId);
  }

  @override
  Future<AppConfig> appConfig() async => const AppConfig();

  /// The sample posts (five per mall), labelled as samples, always on.
  @override
  Future<({Map<String, Object?> json, String? etag})?> posts(String branchId, {String? cursor, String? etag}) async {
    calls.add('posts:$branchId');
    if (cursor == null && etag == 'sample') return null;
    final b = venueRegistry.any((e) => e.id == branchId) ? sampleBranch(branchId) : null;
    return (
      json: <String, Object?>{
        'items': [
          for (final p in postsFor(branchId))
            {
              'id': p.id, 'title': p.title.en, 'body': p.body.en, 'titleTl': p.title.tl, 'bodyTl': p.body.tl, 'motif': p.motif, 'sample': true,
              'author': {'kind': p.author == PostAuthor.store ? 'store' : 'mall', 'name': p.authorName},
              'placeId': ?p.placeId,
              'startsOn': '2026-01-01', 'endsOn': '2099-12-31',
              'branch': {'id': branchId, 'name': b?.name ?? branchId, 'mallName': sampleMallName},
            },
        ],
        'nextCursor': null,
      },
      etag: 'sample',
    );
  }

  /// The samples keep their made-up sample details: no live store info.
  @override
  Future<({Map<String, Object?> json, String? etag})?> live(String branchId, {String? etag}) async =>
      etag == 'sample' ? null : (json: <String, Object?>{'branchId': branchId, 'stores': const []}, etag: 'sample');
}

/// The sample malls already downloaded: blobs and saved-mall records, for tests (and a fresh debug install).
({Map<String, Uint8List> blobs, List<Map<String, Object?>> saved}) sampleInstall(DateTime at, [Iterable<String>? ids]) {
  final which = ids ?? [for (final e in venueRegistry) e.id];
  return (
    blobs: {for (final id in which) SavedMall.key(id, 1): samplePackageBytes(id)},
    saved: [
      for (final id in which)
        SavedMall(id: id, name: sampleBranch(id).name, mallName: sampleMallName, package: sampleMeta(id), savedAt: at).toJson(),
    ],
  );
}
