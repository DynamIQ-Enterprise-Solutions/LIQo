// Routes respect walls: no walking edge passes through a shop, restroom,
// department store or lift/stair core it does not start or end in.
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/features/malls/data/registry.dart';

import '../support/walls.dart';

void main() {
  for (final e in venueRegistry) {
    test('${e.id}: walking never goes through a wall', () {
      final v = e.build(), hits = wallHits(v);
      expect(hits, isEmpty, reason: '${hits.length} edges through walls:\n${hits.map((h) => '  ${v.levels[h.lv].short}: $h').join('\n')}');
    });
  }
}
