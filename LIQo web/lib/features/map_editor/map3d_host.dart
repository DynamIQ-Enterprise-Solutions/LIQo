import 'package:flutter/foundation.dart';

export 'map3d_host_stub.dart' if (dart.library.js_interop) 'map3d_host_web.dart';

/// Asks the 3D preview to frame the whole map again.
class Map3dReset extends ChangeNotifier {
  void fire() => notifyListeners();
}
