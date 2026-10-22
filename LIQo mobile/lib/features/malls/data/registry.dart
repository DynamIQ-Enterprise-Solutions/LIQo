// The offline malls the picker offers, in order. Admin-published maps will
// join (or replace) them once the shopper API exists.
import '../../../core/engine/kit/kit_venue.dart';
import '../../../core/engine/venue.dart';
import 'bayview.dart';
import 'meridian.dart';
import 'spire.dart';

class VenueEntry {
  final String id;
  final Venue Function() build;
  const VenueEntry(this.id, this.build);
}

final venueRegistry = <VenueEntry>[
  VenueEntry('bayview', () => KitVenue(bayviewSpec)),
  VenueEntry('meridian', () => KitVenue(meridianSpec)),
  VenueEntry('spire', () => KitVenue(spireSpec)),
];
