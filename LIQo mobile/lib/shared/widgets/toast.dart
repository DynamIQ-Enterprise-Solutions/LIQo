// A short message over the screen ("Accounts are coming soon"), fading away by
// itself. Built on the overlay, like LIQo web's shared message overlay.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

OverlayEntry? _current;
Timer? _timer;

void showToast(BuildContext context, String text) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _timer?.cancel();
  _current?.remove();
  final entry = OverlayEntry(builder: (context) => _Toast(text: text));
  _current = entry;
  overlay.insert(entry);
  _timer = Timer(const Duration(milliseconds: 2600), () {
    if (_current == entry) {
      entry.remove();
      _current = null;
    }
  });
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.paddingOf(context).bottom + 96,
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          child: Material(
            color: p.ink,
            borderRadius: BorderRadius.circular(14),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(key: const ValueKey('toast'), text, textAlign: TextAlign.center, style: ts(14, w: FontWeight.w600, color: p.panel)),
            ),
          ),
        ),
      ),
    );
  }
}
