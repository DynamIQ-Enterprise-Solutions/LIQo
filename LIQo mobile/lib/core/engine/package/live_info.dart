// A published mall's live store info (docs/shopper-package-format.md §7): the
// stores' names, categories, statuses, hours and contacts, and the lifts,
// escalators and stairs out of service. It changes far more often than the map,
// so it is fetched on every check and applied to the venue's places in place.

/// Minutes from midnight; a close at or before the open runs past midnight (1440 is midnight).
typedef Span = ({int open, int close});

int _min(String hhmm) {
  final p = hhmm.split(':');
  return int.parse(p[0]) * 60 + (p.length > 1 ? int.parse(p[1]) : 0);
}

bool _within(Span s, int m) => s.close > s.open ? m >= s.open && m < s.close : m >= s.open || m < s.close;

/// A special day: closed, or different hours, with an optional short note shown as written.
class SpecialDay {
  const SpecialDay(this.y, this.m, this.d, {this.closed = false, this.span, this.note});
  final int y, m, d;
  final bool closed;
  final Span? span;
  final String? note;
  bool on(DateTime t) => t.year == y && t.month == m && t.day == d;
}

/// What a day holds: its hours (null when closed) and the special day's note, if any.
typedef DayHours = ({Span? span, String? note, bool special});

/// Hours per weekday (1 = Monday) plus special days that override them, in Philippine time.
class WeekHours {
  const WeekHours(this.week, this.specials);
  final Map<int, Span> week;
  final List<SpecialDay> specials;

  static WeekHours? fromJson(Object? j) {
    if (j is! Map) return null;
    final week = <int, Span>{};
    for (final d in (j['week'] as List? ?? const []).cast<Map>()) {
      week[(d['day'] as num).toInt()] = (open: _min(d['open'].toString()), close: _min(d['close'].toString()));
    }
    final specials = <SpecialDay>[];
    for (final s in (j['specials'] as List? ?? const []).cast<Map>()) {
      final date = s['date'].toString().split('-').map(int.parse).toList();
      final closed = s['closed'] == true;
      specials.add(SpecialDay(date[0], date[1], date[2],
          closed: closed, span: closed ? null : (open: _min(s['open'].toString()), close: _min(s['close'].toString())), note: s['note']?.toString()));
    }
    return WeekHours(week, specials);
  }

  /// [t]'s day as written (a wall-clock day in Philippine time).
  DayHours day(DateTime t) {
    final sp = specials.where((s) => s.on(t)).firstOrNull;
    if (sp != null) return (span: sp.span, note: sp.note, special: true);
    return (span: week[t.weekday], note: null, special: false);
  }

  /// Open at [t]: today's hours, or last night's running past midnight.
  bool isOpenAt(DateTime t) {
    final m = t.hour * 60 + t.minute, today = day(t).span;
    if (today != null && (today.close > today.open ? _within(today, m) : m >= today.open)) return true;
    final y = day(t.subtract(const Duration(days: 1))).span;
    return y != null && y.close <= y.open && m < y.close;
  }

  /// When the hours now running end (today's close, or last night's late close).
  int? closesAt(DateTime t) {
    final m = t.hour * 60 + t.minute, today = day(t).span;
    if (today != null && (today.close > today.open ? _within(today, m) : m >= today.open)) return today.close;
    final y = day(t.subtract(const Duration(days: 1))).span;
    return y != null && y.close <= y.open && m < y.close ? y.close : null;
  }

  /// The next opening: later today (0) or tomorrow (1), else null.
  ({int inDays, int at})? nextOpen(DateTime t) {
    final m = t.hour * 60 + t.minute, today = day(t).span;
    if (today != null && today.open > m) return (inDays: 0, at: today.open);
    final tomorrow = day(t.add(const Duration(days: 1))).span;
    return tomorrow == null ? null : (inDays: 1, at: tomorrow.open);
  }
}

/// The app's status key for the web's store status.
String appStatus(String? web) => switch (web) {
      'temporarily_closed' => 'closed',
      'being_repaired' => 'maintenance',
      'opening_soon' => 'comingSoon',
      _ => 'open',
    };

class LiveStore {
  const LiveStore({required this.storeId, required this.spaceIds, required this.name, this.category, this.status = 'open', this.hours, this.hoursNote, this.phone, this.description, this.logoUrl});
  final String storeId, name, status;
  final List<String> spaceIds;
  final String? category, phone, description, logoUrl;
  final WeekHours? hours;

  /// The old free-text hours, shown as written when neither the store nor the mall has hours set.
  final String? hoursNote;

  factory LiveStore.fromJson(Map j) => LiveStore(
        storeId: j['storeId'].toString(),
        spaceIds: [for (final s in j['spaceIds'] as List? ?? const []) s.toString()],
        name: j['name']?.toString() ?? '',
        category: j['category']?.toString(),
        status: appStatus(j['status']?.toString()),
        hours: WeekHours.fromJson(j['hours']),
        hoursNote: j['hoursNote']?.toString(),
        phone: j['phone']?.toString(),
        description: j['description']?.toString(),
        logoUrl: j['logoUrl']?.toString(),
      );
}

/// The app's place categories a store's App category can be.
const storeCats = {'food', 'fashion', 'tech', 'books', 'services', 'other'};

class LiveInfo {
  const LiveInfo({this.branchHours, this.stores = const [], this.outOfService = const {}, this.generatedAt});
  final WeekHours? branchHours;
  final List<LiveStore> stores;
  final Set<String> outOfService;
  final DateTime? generatedAt;

  factory LiveInfo.fromJson(Map j) => LiveInfo(
        branchHours: WeekHours.fromJson(j['branchHours']),
        stores: [for (final s in j['stores'] as List? ?? const []) LiveStore.fromJson(s as Map)],
        outOfService: {for (final o in j['outOfService'] as List? ?? const []) (o as Map)['connectorId'].toString()},
        generatedAt: j['generatedAt'] == null ? null : DateTime.tryParse(j['generatedAt'].toString()),
      );

  /// The store on a space (place id), if any.
  LiveStore? storeOn(String spaceId) => stores.where((s) => s.spaceIds.contains(spaceId)).firstOrNull;
}

/// Philippine wall-clock time (UTC+8) for an instant, which live hours are written in.
DateTime phTime(DateTime t) {
  final u = t.toUtc().add(const Duration(hours: 8));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}
