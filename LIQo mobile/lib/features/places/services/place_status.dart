import '../../../core/engine/package/live_info.dart';
import '../../../core/engine/venue.dart';
import '../../../core/i18n/words.dart';
import '../models/place_info.dart';

/// Whether a place is open, for its chip and its line ("Open · Closes 9:00 PM").
/// The map's own status (closed, being repaired, opening soon) comes first; then
/// the opening hours. Whatever its status, a place can still be routed to; the
/// status is shown beside the way (owner decisions 2026-10-22 and 2026-10-23).
class PlaceStatus {
  const PlaceStatus(this.key, this.line);

  /// open | closedNow | closed | maintenance | comingSoon | note (free-text hours) | unknown
  final String key;
  final String line;

  bool get isOpen => key == 'open';

  /// There is something to say (a published mall's place with no hours has nothing).
  bool get known => key != 'unknown';

  /// Not open now, for sure (closed by the hours or by its status): "You can still get directions."
  bool get notOpen => key == 'closedNow' || key == 'closed' || key == 'maintenance' || key == 'comingSoon';

  /// The chip's key in the status colours.
  String get chip => key == 'closedNow' ? 'closed' : key;
}

PlaceStatus placeStatus(Place p, PlaceInfo info, DateTime now, Words w) {
  switch (p.status) {
    case 'closed':
      return PlaceStatus('closed', w.tr('Temporarily closed'));
    case 'maintenance':
      return PlaceStatus('maintenance', w.tr('Being repaired'));
    case 'comingSoon':
      return PlaceStatus('comingSoon', w.tr('Opening soon'));
  }
  if (info.allDay) return PlaceStatus('open', w.tr('Open 24 hours'));
  final wk = info.week;
  if (wk != null) {
    // live hours are written in Philippine time
    final t = phTime(now), d = wk.day(t), note = d.note;
    String withNote(String s) => note == null || note.isEmpty ? s : '$s · $note';
    final closes = wk.closesAt(t);
    if (closes != null) return PlaceStatus('open', withNote(w.tr('Open · Closes ${OpeningHours.clock(closes)}')));
    if (d.special && d.span == null) return PlaceStatus('closedNow', withNote(w.tr('Closed today')));
    final n = wk.nextOpen(t);
    return PlaceStatus(
      'closedNow',
      withNote(n == null
          ? w.tr('Closed now')
          : n.inDays == 0
              ? w.tr('Closed now · Opens ${OpeningHours.clock(n.at)}')
              : w.tr('Closed now · Opens tomorrow ${OpeningHours.clock(n.at)}')),
    );
  }
  final note = info.hoursNote;
  if (note != null && note.isNotEmpty) return PlaceStatus('note', note);
  if (info.unknown) return const PlaceStatus('unknown', '');
  final h = info.hours;
  if (h == null) return PlaceStatus('open', w.tr('Open'));
  return h.isOpenAt(now)
      ? PlaceStatus('open', w.tr('Open · Closes ${OpeningHours.clock(h.closeMin)}'))
      : PlaceStatus('closedNow', w.tr('Closed now · Opens ${OpeningHours.clock(h.openMin)}'));
}
