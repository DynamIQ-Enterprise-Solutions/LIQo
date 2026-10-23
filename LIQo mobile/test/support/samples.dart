// The sample malls as the app sees downloaded malls: packages from the
// stand-in server, read back with PackageVenue, and the saved-mall records
// that say they are on the phone.
import 'dart:convert';

import 'package:liqo_mobile/core/engine/package/package_venue.dart';
import 'package:liqo_mobile/core/engine/venue.dart';
import 'package:liqo_mobile/core/storage/keys.dart';
import 'package:liqo_mobile/features/malls/data/registry.dart';
import 'package:liqo_mobile/features/malls/data/sample_server.dart';

final allSampleIds = [for (final e in venueRegistry) e.id];

/// Sample malls read back from their packages, the way the app reads a download.
Map<String, Venue> sampleVenues([Iterable<String>? ids]) => {
      for (final id in ids ?? allSampleIds)
        id: PackageVenue((jsonDecode(utf8.decode(samplePackageBytes(id))) as Map).cast<String, Object?>(), id: id, mallName: sampleMallName),
    };

/// The prefs entry that lists sample malls as saved on the phone.
Map<String, String> sampleSavedPrefs(DateTime at, [Iterable<String>? ids]) => {Keys.savedMalls: jsonEncode(sampleInstall(at, ids).saved)};
