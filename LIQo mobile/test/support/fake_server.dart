// A shopper server for tests that can be steered: offline, a newer version of a
// mall, a broken download, a branch switched off, a newer package format, or this
// app version retired. Packages are the sample malls' own, re-versioned.
import 'dart:convert';
import 'dart:typed_data';

import 'package:liqo_mobile/core/data/shopper_api.dart';
import 'package:liqo_mobile/core/engine/package/package_venue.dart';
import 'package:liqo_mobile/features/malls/data/sample_server.dart';

import 'samples.dart';

class FakeShopperApi implements ShopperApi {
  FakeShopperApi() {
    for (final id in allSampleIds) {
      publish(id, 1);
    }
  }

  bool offline = false;
  String? mustUpdateBelow;
  final calls = <String>[];
  final _bytes = <String, Uint8List>{};
  final _meta = <String, PackageMeta>{};
  final _off = <String>{};

  /// Branches the next download serves broken (wrong checksum).
  final corrupt = <String>{};

  final _live = <String, Map<String, Object?>>{}, _liveTag = <String, String>{};
  var _tags = 0;

  final _posts = <String, List<Map<String, Object?>>>{}, _postsTag = <String, String>{};

  /// Sets a branch's posts, newest first (a new ETag each time); served 10 per page.
  void setPosts(String id, List<Map<String, Object?>> posts) {
    _posts[id] = posts;
    _postsTag[id] = 'p${++_tags}';
  }

  /// Sets a branch's live store info (a new ETag each time).
  void setLive(String id, Map<String, Object?> json) {
    _live[id] = json;
    _liveTag[id] = 'e${++_tags}';
  }

  /// Publishes [id] at [version], optionally edited (e.g. a store moved) and in another format.
  void publish(String id, int version, {void Function(Map<String, Object?> pkg)? edit, int format = packageFormatVersion}) {
    final pkg = (jsonDecode(utf8.decode(samplePackageBytes(id))) as Map).cast<String, Object?>()
      ..['version'] = version
      ..['formatVersion'] = format;
    edit?.call(pkg);
    final b = Uint8List.fromList(utf8.encode(jsonEncode(pkg)));
    _bytes[id] = b;
    _meta[id] = PackageMeta(version: version, formatVersion: format, checksum: sha256Hex(b), sizeBytes: b.length);
  }

  /// Switches a branch off (or back on).
  void switchOff(String id, [bool off = true]) => off ? _off.add(id) : _off.remove(id);

  void _net() {
    if (offline) throw const OfflineException('test offline');
  }

  @override
  Future<DirectoryData> directory() async {
    calls.add('directory');
    _net();
    return DirectoryData([
      for (final id in allSampleIds)
        BranchEntry(id: id, name: sampleBranch(id).name, mallId: sampleMallId, mallName: sampleMallName, active: !_off.contains(id), package: _off.contains(id) ? null : _meta[id]),
    ]);
  }

  @override
  Future<Uint8List> package(String branchId, int version) async {
    calls.add('package:$branchId@$version');
    _net();
    final b = _bytes[branchId]!;
    return corrupt.remove(branchId) ? Uint8List.fromList([...b, 32]) : b;
  }

  @override
  Future<({Map<String, Object?> json, String? etag})?> live(String branchId, {String? etag}) async {
    calls.add('live:$branchId');
    _net();
    final j = _live[branchId];
    if (j == null || etag == _liveTag[branchId]) return null;
    return (json: j, etag: _liveTag[branchId]);
  }

  @override
  Future<({Map<String, Object?> json, String? etag})?> posts(String branchId, {String? cursor, String? etag}) async {
    calls.add('posts:$branchId${cursor == null ? '' : '@$cursor'}');
    _net();
    final all = _posts[branchId] ?? const <Map<String, Object?>>[];
    if (cursor == null && etag != null && etag == _postsTag[branchId]) return null;
    final from = int.tryParse(cursor ?? '0') ?? 0, to = (from + 10).clamp(0, all.length);
    return (json: <String, Object?>{'items': all.sublist(from.clamp(0, all.length), to), 'nextCursor': to < all.length ? '$to' : null}, etag: cursor == null ? _postsTag[branchId] : null);
  }

  @override
  Future<AppConfig> appConfig() async {
    _net();
    return AppConfig(mustUpdateBelow: mustUpdateBelow);
  }
}

/// A post as the server sends it (§8), for tests.
Map<String, Object?> fakePost(int id, {String branch = 'bayview', String title = 'Post', String starts = '2026-10-20', String ends = '2026-10-30', int? storeId, String? imageUrl}) => {
      'id': id, 'title': '$title $id', 'body': 'Body of post $id', 'imageUrl': ?imageUrl,
      'author': storeId == null ? {'kind': 'mall', 'name': 'Bayview Grand'} : {'kind': 'store', 'storeId': storeId, 'name': 'Store $storeId'},
      'startsOn': starts, 'endsOn': ends, 'branch': {'id': branch, 'name': 'Bayview Grand', 'mallName': 'LIQo sample malls'},
    };
