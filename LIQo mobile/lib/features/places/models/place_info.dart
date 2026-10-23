// What the place page shows beyond the map's own data: opening hours, a phone,
// a website, an About text and a drawn placeholder picture. For the offline
// malls these are clearly made-up sample values (owner decision 2026-10-22);
// admin data replaces them later.
import 'package:flutter/foundation.dart';

import '../../../core/engine/package/live_info.dart';

/// Opening hours, as minutes from midnight. A close at or before the open time
/// runs past midnight (1440 is midnight itself).
@immutable
class OpeningHours {
  const OpeningHours(this.openMin, this.closeMin);
  final int openMin, closeMin;

  bool isOpenAt(DateTime t) {
    final m = t.hour * 60 + t.minute;
    return closeMin > openMin ? m >= openMin && m < closeMin : m >= openMin || m < closeMin;
  }

  /// "9:00 PM" (12-hour clock, owner decision 2026-10-22).
  static String clock(int min) {
    final h24 = (min ~/ 60) % 24, mm = min % 60;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${mm.toString().padLeft(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}';
  }
}

/// A drawn placeholder picture: what it shows and in which tile colour.
@immutable
class PlaceArt {
  const PlaceArt(this.motif, this.tone, this.seed);

  /// The category glyph drawn in the picture (fashion, food, cinema...).
  final String motif;

  /// Index into the palette's tile colours.
  final int tone;
  final int seed;
}

/// Text in English and Tagalog (data, so it is not run through the app's dictionary).
@immutable
class Bilingual {
  const Bilingual(this.en, this.tl);
  final String en, tl;
  String of(String lang) => lang == 'tl' ? tl : en;
}

@immutable
class PlaceInfo {
  const PlaceInfo({required this.placeId, this.hours, this.week, this.hoursNote, this.phone, this.website, required this.about, required this.art, this.allDay = false, this.unknown = false});
  final String placeId;

  /// A published mall's hours per weekday with special days (live store info, Philippine time).
  final WeekHours? week;

  /// No hours are known for it (a published mall's place without them): no open/closed line.
  final bool unknown;

  /// The store's old free-text hours, shown as written when no hours are set (owner, 2026-10-23).
  final String? hoursNote;

  /// Null when the place has no hours (an exit, a parking zone) or is open all day.
  final OpeningHours? hours;

  /// Open 24 hours (an ATM).
  final bool allDay;
  final String? phone, website;
  final Bilingual about;
  final PlaceArt art;
}
