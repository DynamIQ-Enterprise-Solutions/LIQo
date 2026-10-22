import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A plan picture decoded for the screen. Plans can be 30+ megapixels; drawing
/// that every frame (pan, zoom, the AI scan, the draw-in) is what made the
/// editor lag. So the picture is decoded once at most [maxSide] pixels on its
/// long side, and [original] keeps the real pixel size for every measurement
/// (scale, calibration, boxes), which stays exact.
class PlanImage {
  const PlanImage(this.image, this.original);

  final ui.Image image;
  final ui.Size original;

  static Future<PlanImage> decode(Uint8List bytes, {int maxSide = 4096}) async {
    var original = ui.Size.zero;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (int w, int h) {
        original = ui.Size(w.toDouble(), h.toDouble());
        final s = math.min(1.0, maxSide / math.max(w, h));
        return ui.TargetImageSize(width: math.max(1, (w * s).round()), height: math.max(1, (h * s).round()));
      },
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (original == ui.Size.zero) original = ui.Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    return PlanImage(frame.image, original);
  }
}
