// What each venue draws for itself. The painter draws everything shared on
// top (routes, pins, the dot, the stacked view's frame).
import '../../../core/engine/kit/kit_venue.dart';
import '../../../core/engine/venue.dart';
import 'kit_renderer.dart';
import 'map_painter.dart';

abstract class VenueRenderer {
  /// The site from far away: the ground, then the buildings.
  void siteBase(MapPainter p);

  /// Labels and tappable points on the site view.
  void siteLabels(MapPainter p);

  /// One level's plan: the ground (dimmed above ground level) and the floor.
  void levelBase(MapPainter p, int lv);

  /// One plate of the stacked view.
  void stackPlate(MapPainter p, int lv);
}

final _cache = Expando<VenueRenderer>();

/// The offline malls are kit venues; admin-published maps will get a renderer of their own.
VenueRenderer rendererFor(Venue v) => _cache[v] ??= KitRenderer(v as KitVenue);
