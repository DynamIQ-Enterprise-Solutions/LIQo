import '../../../core/engine/venue.dart';
import '../../../core/i18n/words.dart';
import '../models/place_info.dart';

/// Whether a place is open, for its chip and its line ("Open · Closes 9:00 PM").
/// The map's own status (closed, being repaired, opening soon) comes first; then
/// the opening hours. Whatever its status, a place can still be routed to; the
/// status is shown beside the way (owner decisions 2026-10-22 and 2026-10-23).
class PlaceStatus {
  const PlaceStatus(this.key, this.line);

  /// open | closedNow | closed | maintenance | comingSoon
  final String key;
  final String line;

  bool get isOpen => key == 'open';

  /// The chip's key in the status colours.
  String get chip => key == 'closedNow' ? 'closed' : key;
}

PlaceStatus placeStatus(Place p, PlaceInfo info, DateTime now, Words w) {
  switch (p.status) {
    case 'closed':
      return PlaceStatus('closed', w.tr('Closed'));
    case 'maintenance':
      return PlaceStatus('maintenance', w.tr('Being repaired'));
    case 'comingSoon':
      return PlaceStatus('comingSoon', w.tr('Opening soon'));
  }
  if (info.allDay) return PlaceStatus('open', w.tr('Open 24 hours'));
  final h = info.hours;
  if (h == null) return PlaceStatus('open', w.tr('Open'));
  return h.isOpenAt(now)
      ? PlaceStatus('open', w.tr('Open · Closes ${OpeningHours.clock(h.closeMin)}'))
      : PlaceStatus('closedNow', w.tr('Closed now · Opens ${OpeningHours.clock(h.openMin)}'));
}
