import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../core/theme.dart';
import 'map3d_host.dart';

// The three.js scene in web/map3d/map3d.js (Round 17, US-036), hosted in an
// HTML element inside Flutter. Loaded on first use from the app itself.

extension type _Module._(JSObject _) implements JSObject {
  external _Preview createPreview(web.HTMLElement host);
}

extension type _Preview._(JSObject _) implements JSObject {
  external void update(String json);
  external void resetView();
  external void dispose();
}

_Module? _module;

class Map3dHost extends StatefulWidget {
  const Map3dHost({super.key, required this.payload, required this.reset});

  final String payload;
  final Map3dReset reset;

  @override
  State<Map3dHost> createState() => _Map3dHostState();
}

class _Map3dHostState extends State<Map3dHost> {
  static int _seq = 0;
  final String _viewType = 'liqo-map3d-${_seq++}';
  late final web.HTMLDivElement _div;
  _Preview? _preview;
  String? _error;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _div = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'relative';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _div);
    widget.reset.addListener(_onReset);
    _start();
  }

  Future<void> _start() async {
    try {
      final module = _module ??= await importModule(Uri.parse(web.document.baseURI).resolve('map3d/map3d.js').toString().toJS).toDart as _Module;
      if (_disposed) return;
      _preview = module.createPreview(_div);
      if (widget.payload.isNotEmpty) _preview!.update(widget.payload);
    } catch (e) {
      if (mounted) setState(() => _error = 'The 3D preview could not start. The 2D editor works as usual.');
    }
  }

  void _onReset() => _preview?.resetView();

  @override
  void didUpdateWidget(covariant Map3dHost old) {
    super.didUpdateWidget(old);
    if (old.reset != widget.reset) {
      old.reset.removeListener(_onReset);
      widget.reset.addListener(_onReset);
    }
    if (widget.payload != old.payload && widget.payload.isNotEmpty) _preview?.update(widget.payload);
  }

  @override
  void dispose() {
    _disposed = true;
    widget.reset.removeListener(_onReset);
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (_error != null) {
      return ColoredBox(color: p.bg, child: Center(child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!, textAlign: TextAlign.center, style: ts(12, color: p.muted)))));
    }
    return HtmlElementView(viewType: _viewType);
  }
}
