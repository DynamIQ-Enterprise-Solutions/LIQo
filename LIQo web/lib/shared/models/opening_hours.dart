/// Opening hours (Round 21, owner decisions 2026-10-23; the server's shape in
/// docs/shopper-package-format.md §7): one open–close range per weekday
/// (1 = Monday … 7 = Sunday; a missing day is closed) plus dated special days
/// that override the week. Philippine time, 24-hour "HH:MM", "24:00" is
/// midnight at the end of the day, a close at or before the open runs past
/// midnight.
class DayHours {
  const DayHours({required this.day, required this.open, required this.close});

  final int day;
  final String open;
  final String close;

  factory DayHours.fromJson(Map<String, dynamic> j) => DayHours(day: (j['day'] as num).toInt(), open: j['open'] as String, close: j['close'] as String);
  Map<String, Object?> toJson() => {'day': day, 'open': open, 'close': close};
}

class SpecialDay {
  const SpecialDay({required this.date, this.closed = false, this.open, this.close, this.note});

  /// yyyy-MM-dd.
  final String date;
  final bool closed;
  final String? open;
  final String? close;
  final String? note;

  factory SpecialDay.fromJson(Map<String, dynamic> j) => SpecialDay(
        date: j['date'] as String,
        closed: j['closed'] == true,
        open: j['open'] as String?,
        close: j['close'] as String?,
        note: j['note'] as String?,
      );
  Map<String, Object?> toJson() => {
        'date': date,
        if (closed) 'closed': true else ...{'open': open, 'close': close},
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };
}

class OpeningHours {
  const OpeningHours({this.week = const [], this.specials = const []});

  final List<DayHours> week;
  final List<SpecialDay> specials;

  static OpeningHours? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = j.cast<String, dynamic>();
    return OpeningHours(
      week: [for (final d in (m['week'] as List? ?? const [])) DayHours.fromJson((d as Map).cast<String, dynamic>())],
      specials: [for (final s in (m['specials'] as List? ?? const [])) SpecialDay.fromJson((s as Map).cast<String, dynamic>())],
    );
  }

  Map<String, Object?> toJson() => {
        'week': [for (final d in week) d.toJson()],
        'specials': [for (final s in specials) s.toJson()],
      };

  DayHours? dayOf(int day) {
    for (final d in week) {
      if (d.day == day) return d;
    }
    return null;
  }
}

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "10:00–21:00", with "(next day)" when the close runs past midnight.
String rangeText(String open, String close) {
  final overnight = close != '24:00' && close.compareTo(open) <= 0;
  return '$open–$close${overnight ? ' (next day)' : ''}';
}

/// One line per weekday ("Mon 10:00–21:00", "Sun Closed"), grouping equal neighbours ("Mon–Fri 10:00–21:00").
List<String> weekLines(OpeningHours h) {
  String textOf(int day) {
    final d = h.dayOf(day);
    return d == null ? 'Closed' : rangeText(d.open, d.close);
  }

  final lines = <String>[];
  var start = 1;
  for (var day = 2; day <= 8; day++) {
    if (day == 8 || textOf(day) != textOf(start)) {
      final label = start == day - 1 ? weekdayShort[start - 1] : '${weekdayShort[start - 1]}–${weekdayShort[day - 2]}';
      lines.add('$label ${textOf(start)}');
      start = day;
    }
  }
  return lines;
}

/// "2026-12-25 Closed · Holiday".
String specialText(SpecialDay s) {
  final what = s.closed ? 'Closed' : rangeText(s.open ?? '', s.close ?? '');
  return '${s.date} $what${s.note == null || s.note!.isEmpty ? '' : ' · ${s.note}'}';
}

/// Checks a time typed as "HH:MM" (24-hour) or "24:00".
bool isTime(String? v) => v != null && RegExp(r'^([01]\d|2[0-3]):[0-5]\d$|^24:00$').hasMatch(v.trim());
