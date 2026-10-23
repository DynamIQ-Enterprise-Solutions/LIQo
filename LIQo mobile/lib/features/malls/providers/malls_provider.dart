// The malls on the phone and the LIQo directory (owner decisions 2026-10-23,
// docs/shopper-hybrid-decisions.md §2): a branch is downloaded whole when
// picked and then works offline. The server is asked when the app opens and
// when a saved mall opens; map updates download by themselves on Wi-Fi and wait
// for a tap on mobile data; an update found during a trip in that mall is
// switched in when the trip ends. A branch the server stops offering keeps
// working, "no longer updated". Every download is checked against its checksum
// and saved whole (BlobStore), so a failure always leaves the old copy.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/config.dart';
import '../../../core/data/blob_store.dart';
import '../../../core/data/net.dart';
import '../../../core/data/shopper_api.dart';
import '../../../core/engine/package/live_info.dart';
import '../../../core/engine/package/package_venue.dart';
import '../../../core/engine/venue.dart';
import '../../../core/storage/keys.dart';
import '../../../core/storage/store.dart';
import '../models/saved_mall.dart';

/// Why a download did not happen.
enum DownloadFailure { offline, needsMobileOk, server, corrupt, newerFormat, storage }

@immutable
class MallsState {
  const MallsState({this.saved = const {}, this.venues = const {}, this.directory, this.checkedAt, this.offline = false, this.downloading = const {}, this.booted = false, this.mustUpdate = false, this.liveSeq = 0});

  /// The malls on the phone, by id, in the order they were saved.
  final Map<String, SavedMall> saved;

  /// Their venues, built from the saved packages.
  final Map<String, Venue> venues;

  /// The LIQo directory as last downloaded (kept for offline use), and when.
  final DirectoryData? directory;
  final DateTime? checkedAt;

  /// The last attempt to reach the server failed.
  final bool offline;

  /// Malls being downloaded now.
  final Set<String> downloading;

  /// The saved malls have been read from the phone (at start).
  final bool booted;

  /// The server retired this app version: everything waits for an app update (rare).
  final bool mustUpdate;

  /// Counts live store info applied to the venues (their places change in place), so screens redraw.
  final int liveSeq;

  bool isSaved(String id) => venues.containsKey(id);

  MallsState copyWith({Map<String, SavedMall>? saved, Map<String, Venue>? venues, DirectoryData? directory, DateTime? checkedAt, bool? offline, Set<String>? downloading, bool? booted, bool? mustUpdate, int? liveSeq}) => MallsState(
        saved: saved ?? this.saved, venues: venues ?? this.venues, directory: directory ?? this.directory, checkedAt: checkedAt ?? this.checkedAt,
        offline: offline ?? this.offline, downloading: downloading ?? this.downloading, booted: booted ?? this.booted, mustUpdate: mustUpdate ?? this.mustUpdate,
        liveSeq: liveSeq ?? this.liveSeq,
      );
}

class MallsController extends Notifier<MallsState> {
  static const _directoryKey = 'directory.json';
  static String _liveKey(String id) => 'live/$id.json';

  /// Each mall's live store info (kept on the phone with its ETag, so it works offline).
  final _live = <String, ({LiveInfo info, String? etag})>{};

  void _applyLive(String id, [Venue? venue]) {
    final v = venue ?? state.venues[id], l = _live[id];
    if (v is PackageVenue) v.applyLive(l?.info);
  }

  /// Asks the server for a mall's store info (any network); unchanged replies cost nothing.
  Future<void> _refreshLive(String id) async {
    try {
      final r = await _api.live(id, etag: _live[id]?.etag);
      if (r == null) return;
      final info = LiveInfo.fromJson(r.json);
      _live[id] = (info: info, etag: r.etag);
      try {
        await _blobs.write(_liveKey(id), Uint8List.fromList(utf8.encode(jsonEncode({'etag': r.etag, 'json': r.json}))));
      } catch (_) {} // kept in memory for this session
      _applyLive(id);
      state = state.copyWith(liveSeq: state.liveSeq + 1);
    } catch (e) {
      debugPrint('LIQo: store info for $id not refreshed ($e)');
    }
  }

  /// The out-of-service lifts, escalators and stairs of a mall now.
  Set<String> outOfService(String id) => _live[id]?.info.outOfService ?? const {};

  @override
  MallsState build() {
    final list = ref.read(storeProvider).json(Keys.savedMalls);
    final saved = <String, SavedMall>{};
    for (final j in list is List ? list : const []) {
      final m = SavedMall.fromJson(j);
      if (m != null) saved[m.id] = m;
    }
    final pre = ref.read(preloadedVenuesProvider);
    return MallsState(saved: saved, venues: {for (final id in saved.keys) id: ?pre[id]});
  }

  /// The mall with a trip (or evacuation) in progress, set by the app shell: its updates wait.
  String? tripIn;

  BlobStore get _blobs => ref.read(blobStoreProvider);
  ShopperApi get _api => ref.read(shopperApiProvider);
  DateTime get _now => ref.read(clockProvider)();

  void _persist(Map<String, SavedMall> saved) => ref.read(storeProvider).setJson(Keys.savedMalls, [for (final m in saved.values) m.toJson()]);

  void _setSaved(Map<String, SavedMall> saved, {Map<String, Venue>? venues}) {
    _persist(saved);
    state = state.copyWith(saved: saved, venues: venues);
  }

  static Venue _parse(Uint8List bytes, SavedMall m) =>
      PackageVenue((jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>(), id: m.id, name: m.name, mallName: m.mallName);

  /// At start: the saved malls' packages and the last directory, from the phone. A package that
  /// can't be read is dropped (it can be downloaded again).
  Future<void> boot() async {
    final venues = <String, Venue>{};
    final saved = {...state.saved};
    for (final m in state.saved.values) {
      try {
        final bytes = await _blobs.read(m.blobKey);
        if (bytes == null) throw const FormatException('missing');
        venues[m.id] = _parse(bytes, m);
      } catch (e) {
        debugPrint('LIQo: saved mall ${m.id} could not be read ($e)');
        saved.remove(m.id);
      }
    }
    DirectoryData? dir;
    try {
      final d = await _blobs.read(_directoryKey);
      if (d != null) dir = DirectoryData.fromJson((jsonDecode(utf8.decode(d)) as Map).cast<String, Object?>());
    } catch (_) {}
    for (final id in venues.keys) {
      try {
        final b = await _blobs.read(_liveKey(id));
        if (b == null) continue;
        final j = (jsonDecode(utf8.decode(b)) as Map).cast<String, Object?>();
        _live[id] = (info: LiveInfo.fromJson((j['json']! as Map).cast<String, Object?>()), etag: j['etag']?.toString());
        _applyLive(id, venues[id]);
      } catch (_) {} // unreadable: fetched again on the next check
    }
    if (saved.length != state.saved.length) _persist(saved);
    state = state.copyWith(saved: saved, venues: venues, directory: dir, booted: true);
    // updates that waited for a trip that never ended (the app was closed): switch them in now
    for (final m in saved.values) {
      if (m.pending != null) await applyPending(m.id);
    }
  }

  /// Asks the server for the directory and what's new for the saved malls (when the app opens,
  /// and when a saved mall opens). [tripIn] is the mall with a trip in progress, whose update waits.
  Future<void> checkForUpdates({String? tripIn}) async {
    tripIn ??= this.tripIn;
    final net = await ref.read(netProvider).kind();
    if (net == NetKind.none) {
      state = state.copyWith(offline: true);
      return;
    }
    final DirectoryData dir;
    try {
      dir = await _api.directory();
    } on OfflineException {
      state = state.copyWith(offline: true);
      return;
    } on ServerException {
      state = state.copyWith(offline: true);
      return;
    }
    try {
      final cfg = await _api.appConfig();
      if (cfg.serverTime != null) ref.read(clockSkewProvider.notifier).seen(cfg.serverTime!, DateTime.now());
      final below = cfg.mustUpdateBelow;
      state = state.copyWith(mustUpdate: below != null && versionOlder(appVersion, below));
    } catch (_) {} // no config: carry on
    try {
      await _blobs.write(_directoryKey, Uint8List.fromList(utf8.encode(jsonEncode(dir.toJson()))));
    } catch (_) {} // the directory is a cache: not keeping it is not an error
    final now = _now;
    var saved = {...state.saved};
    for (final m in state.saved.values) {
      final b = dir.branch(m.id);
      if (b == null || !b.offered) {
        saved[m.id] = m.copyWith(retired: true, checkedAt: now, clearOffered: true);
        continue;
      }
      final p = b.package!;
      var upd = m.copyWith(retired: false, checkedAt: now, name: b.name, mallName: b.mallName);
      if (p.version > m.package.version && (m.pending == null || p.version > m.pending!.version)) {
        if (p.formatVersion > packageFormatVersion) {
          upd = upd.copyWith(newerFormat: true, clearOffered: true);
        } else if (net == NetKind.wifi) {
          upd = upd.copyWith(newerFormat: false, clearOffered: true);
          saved[m.id] = upd;
          state = state.copyWith(saved: saved);
          await _fetch(b, pending: tripIn == m.id);
          saved = {...state.saved};
          continue;
        } else {
          upd = upd.copyWith(offered: p, newerFormat: false);
        }
      }
      saved[m.id] = upd;
    }
    _persist(saved);
    state = state.copyWith(saved: saved, directory: dir, checkedAt: now, offline: false);
    for (final m in saved.values) {
      if (!m.retired && state.venues.containsKey(m.id)) await _refreshLive(m.id);
    }
  }

  /// Downloads a mall (first time, or an update the shopper tapped). On mobile data a first
  /// download needs [mobileOk] (the screen asks first). Returns null when it worked.
  Future<DownloadFailure?> download(String id, {bool mobileOk = false, String? tripIn}) async {
    tripIn ??= this.tripIn;
    final net = await ref.read(netProvider).kind();
    if (net == NetKind.none) return DownloadFailure.offline;
    if (net == NetKind.mobile && !mobileOk && !state.saved.containsKey(id)) return DownloadFailure.needsMobileOk;
    var b = state.directory?.branch(id);
    if (b == null || !b.offered) {
      try {
        final dir = await _api.directory();
        state = state.copyWith(directory: dir, checkedAt: _now, offline: false);
        b = dir.branch(id);
      } on OfflineException {
        state = state.copyWith(offline: true);
        return DownloadFailure.offline;
      } on ServerException {
        return DownloadFailure.server;
      }
    }
    if (b == null || !b.offered) return DownloadFailure.server;
    if (b.package!.formatVersion > packageFormatVersion) return DownloadFailure.newerFormat;
    final r = await _fetch(b, pending: tripIn == id);
    if (r == null) await _refreshLive(id);
    return r;
  }

  /// Fetches, checks and saves [b]'s package. With [pending], an update waits for the trip to end.
  Future<DownloadFailure?> _fetch(BranchEntry b, {bool pending = false}) async {
    final meta = b.package!;
    state = state.copyWith(downloading: {...state.downloading, b.id});
    try {
      final Uint8List bytes;
      try {
        bytes = await _api.package(b.id, meta.version);
      } on OfflineException {
        state = state.copyWith(offline: true);
        return DownloadFailure.offline;
      } on ServerException {
        return DownloadFailure.server;
      }
      if (sha256Hex(bytes) != meta.checksum) return DownloadFailure.corrupt;
      final old = state.saved[b.id];
      final m = SavedMall(id: b.id, name: b.name, mallName: b.mallName, package: meta, savedAt: _now, checkedAt: _now);
      final Venue venue;
      try {
        venue = _parse(bytes, m);
      } on PackageFormatException catch (e) {
        return e.newerFormat ? DownloadFailure.newerFormat : DownloadFailure.corrupt;
      }
      try {
        await _blobs.write(SavedMall.key(b.id, meta.version), bytes);
      } on StorageException {
        return DownloadFailure.storage;
      }
      _applyLive(b.id, venue);
      if (pending && old != null) {
        _setSaved({...state.saved, b.id: old.copyWith(pending: meta, clearOffered: true, newerFormat: false)});
        _pendingVenues[b.id] = venue;
        return null;
      }
      _setSaved({...state.saved, b.id: m}, venues: {...state.venues, b.id: venue});
      if (old != null && old.package.version != meta.version) await _blobs.delete(old.blobKey);
      return null;
    } finally {
      state = state.copyWith(downloading: {...state.downloading}..remove(b.id));
    }
  }

  final _pendingVenues = <String, Venue>{};

  /// Switches in an update that waited for a trip to end. True when the mall changed.
  Future<bool> applyPending(String id) async {
    final m = state.saved[id], meta = m?.pending;
    if (m == null || meta == null) return false;
    var venue = _pendingVenues.remove(id);
    final pm = m.copyWith(package: meta, clearPending: true, savedAt: _now);
    if (venue == null) {
      final bytes = await _blobs.read(SavedMall.key(id, meta.version));
      if (bytes == null) {
        _setSaved({...state.saved, id: m.copyWith(clearPending: true)});
        return false;
      }
      venue = _parse(bytes, pm);
    }
    _applyLive(id, venue);
    _setSaved({...state.saved, id: pm}, venues: {...state.venues, id: venue});
    await _blobs.delete(m.blobKey);
    return true;
  }

  /// Removes a mall from the phone. Its saved places, routes and history stay, greyed (owner, 2026-10-23).
  Future<void> delete(String id) async {
    final m = state.saved[id];
    if (m == null) return;
    await _blobs.delete(m.blobKey);
    if (m.pending != null) await _blobs.delete(SavedMall.key(id, m.pending!.version));
    _pendingVenues.remove(id);
    _live.remove(id);
    await _blobs.delete(_liveKey(id));
    _setSaved({...state.saved}..remove(id), venues: {...state.venues}..remove(id));
  }

  /// Bytes a saved mall takes.
  Future<int> sizeOf(String id) => _blobs.sizeOf('packages/$id');
}

final mallsProvider = NotifierProvider<MallsController, MallsState>(MallsController.new);

/// "1.2.0" is older than "1.10": numbers compared part by part, missing parts as 0.
bool versionOlder(String a, String b) {
  List<int> parts(String v) => [for (final x in v.split(RegExp(r'[.+-]'))) int.tryParse(x) ?? 0];
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}

/// Venues already built, used at start for the saved malls they match: tests (the app reads its
/// packages from the phone at start instead, MallsController.boot).
final preloadedVenuesProvider = Provider<Map<String, Venue>>((ref) => const {});
