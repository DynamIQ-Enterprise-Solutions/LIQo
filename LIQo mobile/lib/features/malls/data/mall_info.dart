// The offline malls' own details, for the header, the picker and About. Phone
// numbers are in the fictional 555-01NN range and websites are on example.com,
// so nothing dials or opens a real business (owner decision 2026-10-22).
import '../../places/models/place_info.dart';

class MallInfo {
  const MallInfo({required this.id, required this.hours, required this.phone, required this.website, required this.about});
  final String id;
  final OpeningHours hours;
  final String phone, website;
  final Bilingual about;
}

const mallInfos = {
  'bayview': MallInfo(
    id: 'bayview',
    hours: OpeningHours(10 * 60, 22 * 60),
    phone: '+63 2 5550 0100',
    website: 'https://example.com/bayview',
    about: Bilingual(
      'A bayside campus with a 700 m main mall, an open-air entertainment wing, an arena and a seaside promenade.',
      'Isang campus sa tabi ng look: may 700 m na main mall, open-air na entertainment wing, arena at promenade sa tabing-dagat.',
    ),
  ),
  'meridian': MallInfo(
    id: 'meridian',
    hours: OpeningHours(10 * 60, 21 * 60),
    phone: '+63 2 5550 0101',
    website: 'https://example.com/meridian',
    about: Bilingual(
      'Two mall towers across a street, joined by bridges, with a Fashion Hall and a link to the train station.',
      'Dalawang mall tower sa magkabilang panig ng kalye, pinagdugtong ng mga tulay, may Fashion Hall at daan papunta sa istasyon ng tren.',
    ),
  ),
  'spire': MallInfo(
    id: 'spire',
    hours: OpeningHours(10 * 60, 21 * 60),
    phone: '+63 2 5550 0102',
    website: 'https://example.com/spire',
    about: Bilingual(
      'A 16-level tower mall around a tall atrium, with express escalators and a garden on the roof.',
      'Isang 16 na palapag na tower mall sa paligid ng mataas na atrium, may express escalator at hardin sa bubong.',
    ),
  ),
};
