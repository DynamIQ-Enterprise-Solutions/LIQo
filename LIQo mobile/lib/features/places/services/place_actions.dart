// Call, Website and Share on a place page (owner decision 2026-10-22: they work;
// the sample values are fictional numbers and example.com links). Tests replace
// this with a recorder.
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class PlaceActions {
  const PlaceActions();

  /// Opens the phone's dialer with the number (nothing is dialled until the shopper presses call).
  Future<bool> call(String phone) => launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));

  /// Opens the website in the browser.
  Future<bool> openWebsite(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// The share sheet with plain text ("Opal Comics — Level 3, Bayview Grand"). [origin] anchors it on an iPad.
  Future<void> share(String text, {Rect? origin}) async {
    await SharePlus.instance.share(ShareParams(text: text, sharePositionOrigin: origin));
  }
}

final placeActionsProvider = Provider<PlaceActions>((ref) => const PlaceActions());

/// What Share sends: "Opal Comics — Level 3, Bayview Grand".
String shareText(String place, String level, String mall) => '$place — $level, $mall';
