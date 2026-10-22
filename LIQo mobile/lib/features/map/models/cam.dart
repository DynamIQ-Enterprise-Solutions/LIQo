import 'dart:math' as math;

import '../../../core/engine/util.dart';
import '../../../core/engine/venue.dart';
import '../services/map_constants.dart';

/// The map camera (the demo's `cam`): where it looks, how close, the 3D tilt,
/// how far the stacked view is opened, and the two-finger rotation.
class Cam {
  double zoom = 1, cx = 255, cy = 380, tilt = 1, ex = 0; // ex: 0 = normal, 1 = fully stacked
  double rot = 0; // two-finger rotation, on top of [yaw]
  // derived by prep()
  double kyB = 0, kzB = 0, S = 0, c = 1, s = 0; // ignore: non_constant_identifier_names

  /// The demo's prep(), with the venue's scale and stacked-view settings.
  void prep(Venue v) {
    final st = v.stack, t = smooth((zoom - 1) / 1.6), yw = lerp(yaw + rot, st.yaw, ex);
    kyB = lerp(lerp(0.82, 0.66, t), st.ky, ex);
    kzB = lerp(lerp(0.6, 0.74, t), st.kz, ex);
    S = lerp(v.basePx * zoom, st.s, ex);
    c = math.cos(yw);
    s = math.sin(yw);
  }
}
