import 'package:flutter/widgets.dart';

import '../../../navigation/models/nav_state.dart';
import '../../../navigation/providers/nav_provider.dart';
import '../../../navigation/services/nav_text.dart';
import '../../../settings/models/app_settings.dart';
import '../../providers/map_provider.dart';

/// Gives the map's panels the navigation, the camera and the words without
/// passing them down by hand (the demo's Scope). Rebuilt with every change.
class MapScope extends InheritedWidget {
  const MapScope({super.key, required this.s, required this.mv, required this.t, required this.nav, required this.map, required this.settings, required this.mallId, required this.version, required this.onFoldRail, required this.onFoldLevels, required super.child});

  final NavState s;
  final MapView mv;
  final NavText t;
  final NavController nav;
  final MapController map;
  final AppSettings settings;
  final String mallId;
  final int version;

  /// Folding the tool rail and the level chips (saved in the settings).
  final VoidCallback onFoldRail, onFoldLevels;

  String tr(String en) => t.tr(en);

  static MapScope of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<MapScope>()!;

  @override
  bool updateShouldNotify(MapScope old) => old.version != version || !identical(old.t, t) || old.settings != settings;
}
