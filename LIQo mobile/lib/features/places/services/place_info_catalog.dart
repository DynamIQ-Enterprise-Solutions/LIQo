// The sample details of the offline malls' places, worked out from the place
// itself, so they are the same on every launch: the mall's hours (food courts
// later, cinemas and the arena on their own hours, ATMs all day), a phone in the
// fictional 555-01NN range, a website on example.com, and an About text per
// category in English and Tagalog. A published mall's places take theirs from
// its live store info instead (hours per day, contacts, description); with no
// hours of its own a store uses the mall's, and with none at all nothing is
// said about being open (owner decisions 2026-10-23).
import '../../../core/engine/package/package_venue.dart';
import '../../../core/engine/venue.dart';
import '../../malls/data/mall_info.dart';
import '../models/place_info.dart';

/// A small stable hash (FNV-1a), so a place always gets the same sample values.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// "Opal Comics" -> "opal-comics".
String slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

const _about = <String, Bilingual>{
  'fashion': Bilingual('{name} carries clothing, shoes and accessories for every day and every occasion.', 'May damit, sapatos at accessories ang {name} para sa araw-araw at sa bawat okasyon.'),
  'food': Bilingual('{name} serves freshly made meals, snacks and drinks to eat in or take away.', 'Naghahain ang {name} ng bagong lutong pagkain, meryenda at inumin, kainin dito o i-take out.'),
  'tech': Bilingual('{name} sells phones, gadgets and accessories, with help to set them up.', 'Nagbebenta ang {name} ng mga phone, gadget at accessories, at may tulong sa pag-set up.'),
  'books': Bilingual('{name} has books, stationery, comics and games for all ages.', 'May mga libro, stationery, komiks at laro ang {name} para sa lahat ng edad.'),
  'services': Bilingual('{name} offers everyday services, from health and beauty to repairs.', 'Nag-aalok ang {name} ng pang-araw-araw na serbisyo, mula kalusugan at pagpapaganda hanggang pag-aayos.'),
  'other': Bilingual('{name} has gifts and things for the home, chosen to make everyday life easier.', 'May mga regalo at gamit sa bahay ang {name}, pinili para gumaan ang araw-araw.'),
  'cinema': Bilingual('{name} shows the latest films on big screens, with snacks at the counter.', 'Ipinapalabas ng {name} ang mga pinakabagong pelikula sa malalaking screen, may meryenda sa counter.'),
  'arena': Bilingual("{name} hosts concerts, games and shows. Check the schedule for today's events.", 'Dito ginaganap ang mga konsiyerto, laro at palabas sa {name}. Tingnan ang iskedyul para sa mga event ngayon.'),
  'garden': Bilingual('{name} is an open-air garden to rest in, with seats and shade.', 'Ang {name} ay hardin sa labas para magpahinga, may upuan at lilim.'),
  'restroom': Bilingual('Restrooms, with baby-changing and accessible stalls.', 'Mga CR, may lugar para magpalit ng diaper ng sanggol at stall para sa may kapansanan.'),
  'atm': Bilingual('A cash machine. Cards from most banks are accepted.', 'Makina ng pera. Tinatanggap ang card ng karamihan sa mga bangko.'),
  'info': Bilingual('Ask here for directions, lost items, wheelchairs and anything else you need.', 'Magtanong dito para sa direksyon, nawawalang gamit, wheelchair at iba pang kailangan mo.'),
  'exit': Bilingual('A way in and out of the building.', 'Daan papasok at palabas ng gusali.'),
  'parking': Bilingual('Parking for cars. Follow the signs to the nearest lift or stairs.', 'Paradahan ng sasakyan. Sundan ang mga karatula papunta sa pinakamalapit na elevator o hagdan.'),
  'ev': Bilingual('Charging points for electric cars.', 'Charging point para sa de-kuryenteng sasakyan.'),
  'lift': Bilingual('{name} goes between the floors it stops at. Step-free.', 'Bumibiyahe ang {name} sa pagitan ng mga palapag na hinihintuan nito. Walang hagdan.'),
  'escalator': Bilingual('{name} runs between the floors it joins.', 'Umaandar ang {name} sa pagitan ng mga palapag na pinagdudugtong nito.'),
  'stairs': Bilingual('{name} joins the floors it serves.', 'Pinagdudugtong ng {name} ang mga palapag na sinisilbihan nito.'),
  'ramp': Bilingual('{name} is a step-free way between floors.', 'Ang {name} ay daan sa pagitan ng mga palapag na walang hagdan.'),
};
const _aboutDefault = Bilingual('{name} is open to everyone.', 'Bukas sa lahat ang {name}.');

/// The motif drawn for a category in the placeholder picture.
String motifOf(String cat) => switch (cat) {
      'fashion' || 'food' || 'tech' || 'books' || 'services' || 'cinema' || 'arena' || 'garden' || 'restroom' || 'atm' || 'info' || 'exit' || 'parking' || 'ev' || 'lift' || 'escalator' || 'stairs' || 'ramp' => cat,
      _ => 'other',
    };

PlaceInfo placeInfoFor(Venue v, Place p) {
  if (v is PackageVenue && mallInfos[v.id] == null) return _published(v, p);
  final mall = mallInfos[v.id], h = stableHash('${v.id}/${p.id}');
  final shop = p.kind == 'store' || p.kind == 'box';
  OpeningHours? hours;
  var allDay = false;
  if (p.cat == 'atm') {
    allDay = true;
  } else if (p.cat == 'cinema') {
    hours = const OpeningHours(11 * 60, 24 * 60);
  } else if (p.cat == 'arena') {
    hours = const OpeningHours(9 * 60, 23 * 60);
  } else if (p.cat == 'food' && mall != null) {
    hours = OpeningHours(mall.hours.openMin, mall.hours.closeMin + 60);
  } else if ((shop || p.cat == 'restroom' || p.cat == 'info' || p.cat == 'garden') && mall != null) {
    hours = mall.hours;
  }
  final about = _about[p.cat] ?? _aboutDefault;
  return PlaceInfo(
    placeId: p.id,
    hours: hours,
    allDay: allDay,
    // 03..99: 00..02 are the malls' own numbers
    phone: shop ? '+63 2 5550 01${(3 + h % 97).toString().padLeft(2, '0')}' : null,
    website: shop ? 'https://example.com/${v.id}/${slug(p.name)}' : null,
    about: Bilingual(about.en.replaceAll('{name}', p.name), about.tl.replaceAll('{name}', p.name)),
    art: PlaceArt(motifOf(p.cat), h % 8, h),
  );
}

/// A published mall's place: its store's live details, or the mall's hours for the shops and
/// services that keep them (restrooms, desks). Exits, parking, lifts and ATMs have no hours line.
PlaceInfo _published(PackageVenue v, Place p) {
  final h = stableHash('${v.id}/${p.id}'), st = v.live?.storeOn(p.id);
  final shop = p.kind == 'store' || p.kind == 'box';
  final usesMallHours = shop || p.cat == 'restroom' || p.cat == 'info' || p.cat == 'food' || p.cat == 'atm';
  final week = st?.hours ?? (usesMallHours ? v.live?.branchHours : null);
  final desc = st?.description;
  final about = desc != null && desc.isNotEmpty ? Bilingual(desc, desc) : Bilingual(p.name, p.name);
  return PlaceInfo(
    placeId: p.id,
    week: week,
    hoursNote: week == null ? st?.hoursNote : null,
    logoUrl: st?.logoUrl,
    unknown: week == null && (st?.hoursNote ?? '').isEmpty,
    phone: st?.phone,
    about: about,
    art: PlaceArt(motifOf(p.cat), h % 8, h),
  );
}
