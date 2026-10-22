import 'package:flutter/material.dart';

import 'favicon.dart';

/// Keeps the browser-tab icon in step with the mode the app is showing
/// (device setting or the person's own pick).
class FaviconSync extends StatefulWidget {
  const FaviconSync({super.key, required this.child});

  final Widget child;

  @override
  State<FaviconSync> createState() => _FaviconSyncState();
}

class _FaviconSyncState extends State<FaviconSync> {
  bool? _dark;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark != _dark) {
      _dark = dark;
      setFavicon(dark: dark);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
