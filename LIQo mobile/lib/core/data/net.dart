// Which connection the phone has: map updates download by themselves only on
// Wi-Fi; on mobile data they wait for a tap (owner decision 2026-10-23).
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NetKind { none, wifi, mobile, other }

abstract class Net {
  Future<NetKind> kind();
}

class DeviceNet implements Net {
  final _c = Connectivity();
  @override
  Future<NetKind> kind() async {
    try {
      final r = await _c.checkConnectivity();
      if (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)) return NetKind.wifi;
      if (r.contains(ConnectivityResult.mobile)) return NetKind.mobile;
      if (r.isEmpty || r.every((x) => x == ConnectivityResult.none)) return NetKind.none;
      return NetKind.other;
    } catch (_) {
      return NetKind.other; // unknown: try the server and let it decide
    }
  }
}

/// A fixed answer: tests.
class FixedNet implements Net {
  FixedNet(this.value);
  NetKind value;
  @override
  Future<NetKind> kind() async => value;
}

/// The connection; main() uses the device's, tests a [FixedNet].
final netProvider = Provider<Net>((ref) => FixedNet(NetKind.wifi));
