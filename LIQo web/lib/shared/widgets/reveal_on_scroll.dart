import 'package:flutter/material.dart';

/// Tells its child when it has scrolled into view, once. Charts use it to
/// grow into place only when the person reaches them, not all at page load.
///
/// The check runs after the first frame and on every scroll of the enclosing
/// scrollable until the widget is seen. Reduced-motion devices are "seen" at once.
class RevealOnScroll extends StatefulWidget {
  const RevealOnScroll({super.key, required this.builder});

  final Widget Function(BuildContext context, bool shown) builder;

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<RevealOnScroll> {
  bool _shown = false;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _shown = true;
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_check);
      _position = position;
      _position?.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_shown || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final screen = MediaQuery.sizeOf(context).height;
    // Visible once a meaningful part of it is on screen.
    if (top < screen - 60 && bottom > 60) {
      _position?.removeListener(_check);
      setState(() => _shown = true);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _shown);
}
