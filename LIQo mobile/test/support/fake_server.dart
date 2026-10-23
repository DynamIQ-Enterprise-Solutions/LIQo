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
  Future<AppConfig> appConfig() async {
    _net();
    return AppConfig(mustUpdateBelow: mustUpdateBelow);
  }
}
