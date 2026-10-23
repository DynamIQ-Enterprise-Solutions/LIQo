import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme.dart';
import '../../shared/widgets/common.dart';
import '../auth/glass.dart';
import 'maps_service.dart';
import 'plan_image.dart';

/// While the AI reads a plan (Round 17, owner decision: a full-screen dialog):
/// the plan, or the boxed part of it, with a soft glowing scan line sweeping
/// over it and the reading grid lighting up behind the line. No invented steps
/// or percentages, only the elapsed time. [done] gives null when the reading
/// worked (the dialog closes itself) or the error in words: then the scan stops
/// and the dialog says what happened, calmly, with Try again and Close
/// (owner, 2026-10-22: graceful error handling). Returns true for Try again.
///
/// Kept light so it runs smoothly with very large plans: the picture is decoded
/// once at screen size, the still part (plan, grid, brackets) is drawn once in
/// its own layer, only the thin line layer moves, and the card has no live blur.
Future<bool> showAiScan(BuildContext context,
    {required Future<String?> done, required int branchId, required String backdropKey, List<double>? crop, @visibleForTesting Future<ui.Image?> Function()? loadImage}) async {
  final retry = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Reading the plan',
    barrierColor: context.pal.scrim,
    transitionDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, __) => AiScanDialog(done: done, branchId: branchId, backdropKey: backdropKey, crop: crop, loadImage: loadImage),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut), child: child),
  );
  return retry == true;
}

class AiScanDialog extends StatefulWidget {
  const AiScanDialog({super.key, required this.done, required this.branchId, required this.backdropKey, this.crop, this.loadImage});

  final Future<String?> done;
  final int branchId;
  final String backdropKey;
  final List<double>? crop;
  final Future<ui.Image?> Function()? loadImage;

  @override
  State<AiScanDialog> createState() => _AiScanDialogState();
}

class _AiScanDialogState extends State<AiScanDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  ui.Image? _image;
  final _seconds = ValueNotifier<int>(0);
  Timer? _clock;
  bool _closed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // Only the clock text rebuilds each second, not the dialog.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _seconds.value++);
    widget.done.then(_finished, onError: (Object e) => _finished('The reading could not be finished. Try again in a moment.'));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_error != null) {
      return;
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _scan.stop();
      _scan.value = 0.5;
    } else if (!_scan.isAnimating) {
      _scan.repeat();
    }
  }

  Future<void> _load() async {
    try {
      ui.Image? img;
      if (widget.loadImage != null) {
        img = await widget.loadImage!();
      } else {
        // A boxed part is shown larger, so it is decoded with more detail.
        final share = widget.crop == null ? 1.0 : math.max(widget.crop![2] - widget.crop![0], widget.crop![3] - widget.crop![1]).clamp(0.2, 1.0);
        final bytes = await MapsService().backdropBytes(widget.branchId, widget.backdropKey);
        img = (await PlanImage.decode(bytes, maxSide: math.min(4096, (2048 / share).round()))).image;
      }
      if (mounted) setState(() => _image = img);
    } catch (_) {
      // The scan still shows over a plain sheet if the picture cannot be loaded.
    }
  }

  void _finished(String? error) {
    if (!mounted) return;
    if (error != null) {
      // The scan stops and the dialog explains; nothing closes under the person.
      _clock?.cancel();
      _scan.stop();
      setState(() => _error = error);
      return;
    }
    _close(false);
  }

  void _close(bool retry) {
    if (_closed || !mounted) return;
    _closed = true;
    // After the current frame, so a reading that ends at once still closes cleanly.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(retry);
    });
    // The dialog may be still (failed, or reduced motion): ask for that frame.
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _seconds.dispose();
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final still = MediaQuery.disableAnimationsOf(context);
    final size = MediaQuery.sizeOf(context);
    final pad = size.width < 600 ? 12.0 : 36.0;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(pad),
          // The card's glass look without a live blur (a full-screen blur
          // redrawn every frame was part of the lag).
          child: DecoratedBox(
            decoration: innerGlass(p, radius: 22).copyWith(color: p.panel.withValues(alpha: p.mix(0.94, 0.9))),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(_error == null ? Icons.auto_awesome : Icons.info_outline, size: 18, color: _error == null ? p.brand2 : p.warn),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error == null ? 'The AI is reading the plan' : 'The plan could not be read this time',
                          key: const ValueKey('ai-scan-title'),
                          style: ts(16, w: FontWeight.w800, color: p.ink),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ValueListenableBuilder<int>(
                        valueListenable: _seconds,
                        builder: (context, s, _) => Text('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}', key: const ValueKey('ai-scan-clock'), style: ts(13, w: FontWeight.w700, color: p.muted)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _error ?? (widget.crop == null ? 'Walls, doors, rooms and their names. A large plan can take a few minutes.' : 'The boxed part of the plan. A large part can take a few minutes.'),
                    key: const ValueKey('ai-scan-message'),
                    style: ts(12, color: _error == null ? p.muted : p.ink),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: ColoredBox(
                        color: p.pick(Colors.white, p.shell),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Drawn once (and again only when the picture or size changes).
                            RepaintBoundary(
                              child: CustomPaint(
                                key: const ValueKey('ai-scan-canvas'),
                                painter: _PlanPainter(image: _image, crop: widget.crop, glow: p.brand, grid: p.brand2, dark: p.darkness),
                              ),
                            ),
                            // The moving line: a thin layer repainted on its own.
                            if (_error == null)
                              RepaintBoundary(
                                child: CustomPaint(painter: _LinePainter(scan: _scan, image: _image, crop: widget.crop, still: still, glow: p.brand, grid: p.brand2)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_error == null)
                    Text('Nothing is added to the map until you review it.', style: ts(11, color: p.sideNote))
                  else
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        AppButton(label: 'Close', onPressed: () => _close(false)),
                        AppButton(label: 'Try again', icon: Icons.refresh, primary: true, onPressed: () => _close(true)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the plan sits in the sheet (its boxed part, fitted with a margin).
Rect _planRect(ui.Image? img, List<double>? crop, Size size) {
  if (img == null) return Rect.fromLTWH(16, 16, math.max(0, size.width - 32), math.max(0, size.height - 32));
  final b = crop ?? const [0.0, 0.0, 1.0, 1.0];
  final w = (b[2] - b[0]) * img.width;
  final h = (b[3] - b[1]) * img.height;
  final s = math.min((size.width - 32) / w, (size.height - 32) / h);
  return Rect.fromCenter(center: size.center(Offset.zero), width: w * s, height: h * s);
}

class _PlanPainter extends CustomPainter {
  _PlanPainter({required this.image, required this.crop, required this.glow, required this.grid, required this.dark});

  final ui.Image? image;
  final List<double>? crop;
  final Color glow;
  final Color grid;
  final double dark;

  @override
  void paint(Canvas c, Size size) {
    final img = image;
    final dst = _planRect(img, crop, size);
    if (img != null) {
      final b = crop ?? const [0.0, 0.0, 1.0, 1.0];
      final src = Rect.fromLTRB(b[0] * img.width, b[1] * img.height, b[2] * img.width, b[3] * img.height);
      final paint = Paint()..filterQuality = FilterQuality.medium;
      // In dark mode the white paper is turned dark so the sheet does not glare.
      if (dark > 0.5) paint.colorFilter = const ColorFilter.matrix([-0.85, 0, 0, 0, 235, 0, -0.85, 0, 0, 235, 0, 0, -0.85, 0, 235, 0, 0, 0, 1, 0]);
      c.drawImageRect(img, src, dst, paint);
    }
    // The reading grid as the AI sees it (every 1/20), faint.
    final line = Paint()
      ..color = grid.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var k = 1; k < 20; k++) {
      final gx = dst.left + dst.width * k / 20;
      final gy = dst.top + dst.height * k / 20;
      c.drawLine(Offset(dst.left, gy), Offset(dst.right, gy), line);
      c.drawLine(Offset(gx, dst.top), Offset(gx, dst.bottom), line);
    }
    // Corner brackets around the part being read.
    final br = Paint()
      ..color = glow.withValues(alpha: 0.9)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final l = math.min(28.0, dst.shortestSide / 6);
    for (final (o, dx, dy) in [(dst.topLeft, 1.0, 1.0), (dst.topRight, -1.0, 1.0), (dst.bottomLeft, 1.0, -1.0), (dst.bottomRight, -1.0, -1.0)]) {
      c.drawLine(o, o + Offset(l * dx, 0), br);
      c.drawLine(o, o + Offset(0, l * dy), br);
    }
  }

  @override
  bool shouldRepaint(covariant _PlanPainter old) => old.image != image || old.dark != dark || old.glow != glow || old.crop != crop;
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.scan, required this.image, required this.crop, required this.still, required this.glow, required this.grid}) : super(repaint: scan);

  final Animation<double> scan;
  final ui.Image? image;
  final List<double>? crop;
  final bool still;
  final Color glow;
  final Color grid;

  @override
  void paint(Canvas c, Size size) {
    final dst = _planRect(image, crop, size);
    final t = scan.value;
    final y = still ? dst.center.dy : dst.top + dst.height * Curves.easeInOutSine.transform(t <= 0.5 ? t * 2 : 2 - t * 2);
    // Grid rows light up as the line passes.
    for (var k = 1; k < 20; k++) {
      final gy = dst.top + dst.height * k / 20;
      final near = (1 - ((gy - y).abs() / (dst.height * 0.2))).clamp(0.0, 1.0);
      if (near <= 0) continue;
      c.drawLine(
          Offset(dst.left, gy),
          Offset(dst.right, gy),
          Paint()
            ..color = grid.withValues(alpha: 0.2 * near)
            ..strokeWidth = 1);
    }
    // A soft glow band with a bright core.
    final band = math.max(30.0, dst.height * 0.08);
    final rect = Rect.fromLTRB(dst.left, y - band, dst.right, y + band);
    c.drawRect(rect, Paint()..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [glow.withValues(alpha: 0), glow.withValues(alpha: 0.22), glow.withValues(alpha: 0)], [0, 0.5, 1]));
    c.drawLine(
        Offset(dst.left, y),
        Offset(dst.right, y),
        Paint()
          ..color = glow.withValues(alpha: 0.95)
          ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.image != image || old.still != still || old.glow != glow || old.crop != crop;
}
