// Tap targets recorded while the map paints, standing in for the SVG's
// data-poi / data-bldg / data-level groups and `elementFromPoint().closest()`.
import 'dart:ui';

class Hit {
  final String kind; // poi | bldg | level
  final String id;
  final Path path;
  const Hit(this.kind, this.id, this.path);
}

class MapHits {
  final List<Hit> _list = [];
  void clear() => _list.clear();
  void add(String kind, String id, Path path) => _list.add(Hit(kind, id, path));

  /// The topmost (last painted) group under the point.
  Hit? at(Offset p) {
    for (var i = _list.length - 1; i >= 0; i--) {
      if (_list[i].path.contains(p)) return _list[i];
    }
    return null;
  }
}
