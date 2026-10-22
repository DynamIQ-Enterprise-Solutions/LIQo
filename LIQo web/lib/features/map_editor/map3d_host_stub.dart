import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'map3d_host.dart';

/// Outside the browser (tests) there is no WebGL: a quiet placeholder.
class Map3dHost extends StatelessWidget {
  const Map3dHost({super.key, required this.payload, required this.reset});

  final String payload;
  final Map3dReset reset;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ColoredBox(
      color: p.bg,
      child: Center(child: Text('3D preview', key: const ValueKey('map3d-placeholder'), style: ts(12, color: p.sideNote))),
    );
  }
}
