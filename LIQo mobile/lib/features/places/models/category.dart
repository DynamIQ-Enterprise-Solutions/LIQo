// The categories on Home and on the map (the board's tiles and chips). Shops is
// every store-type place but food, anchors, cinemas and the arena included;
// Elevators is one row per lift bank; Parking lists the parking areas
// (owner decisions 2026-10-22).
import 'package:flutter/material.dart';

import '../../../core/engine/venue.dart';
import '../../navigation/models/nav_state.dart';

class Category {
  const Category(this.id, this.label, this.glyph, this.icon);

  /// shops | food | restroom | lift | atm | parking (also the map's "nearest" type)
  final String id;
  final String label;

  /// The map's line icon, and the Material icon of the other screens.
  final String glyph;
  final IconData icon;

  /// Every place of this category in the mall (lifts as places, at the shopper's floor when they stop there).
  List<Place> placesIn(NavState s) {
    if (id == 'lift') {
      return [for (final c in s.v.connectors) if (c.type == 'lift') s.connPlace(c.id)].whereType<Place>().toList();
    }
    return s.v.places.where(has).toList();
  }

  bool has(Place p) => switch (id) {
        'shops' => isShop(p) && p.cat != 'food',
        'food' => isShop(p) && p.cat == 'food',
        'parking' => p.kind == 'zone',
        _ => p.cat == id,
      };

  static bool isShop(Place p) => p.kind == 'store' || p.kind == 'box';
}

const categories = [
  Category('shops', 'Shops', 'g-other', Icons.shopping_bag_outlined),
  Category('food', 'Food & Dining', 'g-food', Icons.restaurant),
  Category('restroom', 'Restrooms', 'g-restroom', Icons.wc),
  Category('lift', 'Elevators', 'g-lift', Icons.elevator_outlined),
  Category('atm', 'ATMs', 'g-atm', Icons.atm),
  Category('parking', 'Parking', 'g-parking', Icons.local_parking),
];

Category categoryById(String id) => categories.firstWhere((c) => c.id == id, orElse: () => categories.first);

/// The Material icon of a kind of place, for the screens outside the map.
IconData iconOfCat(String cat) => switch (cat) {
      'fashion' => Icons.checkroom,
      'food' => Icons.restaurant,
      'tech' => Icons.devices_other,
      'books' => Icons.menu_book,
      'services' => Icons.room_service_outlined,
      'cinema' => Icons.movie_outlined,
      'arena' => Icons.stadium_outlined,
      'garden' => Icons.park_outlined,
      'restroom' => Icons.wc,
      'atm' => Icons.atm,
      'info' => Icons.info_outline,
      'exit' => Icons.door_front_door_outlined,
      'parking' => Icons.local_parking,
      'ev' => Icons.ev_station_outlined,
      'lift' => Icons.elevator_outlined,
      'escalator' => Icons.escalator,
      'stairs' => Icons.stairs_outlined,
      'ramp' => Icons.accessible,
      _ => Icons.shopping_bag_outlined,
    };
