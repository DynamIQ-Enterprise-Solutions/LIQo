// For everyone: settings and route options that are saved, walking pace, stairs
// and escalators avoided strictly with a fallback note, and high contrast (from
// the demo's access_test; the text-size screen test is in test/app).
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/engine/routing.dart';
import 'package:liqo_mobile/core/storage/keys.dart';
import 'package:liqo_mobile/core/theme.dart';
import 'package:liqo_mobile/features/navigation/models/route_options.dart';
import 'package:liqo_mobile/features/navigation/providers/route_options_provider.dart';
import 'package:liqo_mobile/features/saved/providers/saved_providers.dart';
import 'package:liqo_mobile/features/settings/models/app_settings.dart';
import 'package:liqo_mobile/features/settings/providers/settings_provider.dart';

import '../support/harness.dart';
import '../support/spots.dart';

Set<String> hopTypes(RouteT r) => {for (final s in r.seg) if (isHop(s)) s!.ctype!};

/// WCAG contrast ratio between two colours.
double contrast(Color a, Color b) {
  double lum(Color c) {
    double g(double v) => v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
    return .2126 * g(c.r) + .7152 * g(c.g) + .0722 * g(c.b);
  }

  final l1 = lum(a), l2 = lum(b);
  return l1 > l2 ? (l1 + .05) / (l2 + .05) : (l2 + .05) / (l1 + .05);
}

void main() {
  group('saving', () {
    test('settings, route options and favourites are kept; trips and positions are not', () {
      final h1 = Harness();
      h1.settings
        ..setLang('tl')
        ..setTextSize(1.4)
        ..setHighContrast(true)
        ..setPace('slow')
        ..setTheme('dark');
      h1.options.setAvoidStairs(true);
      h1.c.read(favouritesProvider.notifier).toggle('bayview', 'G-EHM');
      h1.goFrom(scenarioStart(h1.v), '3-M1');
      expect(jsonDecode(h1.store.get(Keys.settings)!)['pace'], 'slow');

      final h2 = Harness(prefs: {for (final k in [Keys.settings, Keys.routeOptions, Keys.favourites, Keys.history]) k: h1.store.get(k)!});
      final s = h2.c.read(settingsProvider);
      expect((s.lang, s.textSize, s.highContrast, s.pace, s.theme), ('tl', 1.4, true, 'slow', 'dark'));
      expect(h2.c.read(routeOptionsProvider).avoidStairs, isTrue);
      expect(h2.c.read(favouritesProvider.notifier).isFav('bayview', 'G-EHM'), isTrue);
      expect(h2.s.user, isNull); // no position is kept
      expect(h2.s.route, isNull);
    });

    test('a broken or foreign saved value falls back to the defaults', () {
      expect(AppSettings.fromJson(null).lang, 'en');
      final s = AppSettings.fromJson(jsonDecode('{"lang":"fr","textSize":9,"pace":42,"theme":"dark"}'));
      expect((s.lang, s.textSize, s.pace, s.theme), ('en', 1.0, 'normal', 'dark'));
      final h = Harness(prefs: {Keys.settings: '{"lang":"fr"', Keys.routeOptions: '[1,2]'});
      expect(h.c.read(settingsProvider), const AppSettings());
      expect(h.c.read(routeOptionsProvider), const RouteOptions());
    });
  });

  test('walking pace changes the minutes and nothing else about the route', () {
    final h = Harness();
    h.goFrom(scenarioStart(h.v), '3-M1');
    final total = h.s.route!.total;
    // 600 m at 1.4 m/s is about 7 minutes
    for (final (pace, eta) in [('normal', '8 min'), ('slow', '13 min'), ('relaxed', '10 min'), ('brisk', '6 min'), ('fast', '5 min')]) {
      h.settings.setPace(pace);
      expect(h.text.fmtEta(600), eta, reason: pace);
    }
    expect(h.s.route!.total, total);
  });

  test('the simulated walk moves at the chosen pace: 1.4 m/s normal, +25% brisk, +50% fast', () {
    for (final (pace, mps) in [('slow', 1.4 / 1.7), ('relaxed', 1.4 / 1.3), ('normal', 1.4), ('brisk', 1.75), ('fast', 2.1)]) {
      final h = Harness()..settings.setPace(pace);
      h.goFrom(scenarioStart(h.v), 'G-ARENA');
      h.nav.start();
      h.nav.tickerStarted();
      for (var ms = 0; ms <= 2000; ms += 50) {
        h.nav.tick(Duration(milliseconds: ms));
      }
      expect(h.s.route!.progress / 2, closeTo(mps, .01), reason: pace);
    }
  });

  group('avoid stairs / escalators', () {
    test('strict: the trip up takes the lift instead of the escalator', () {
      final h = Harness();
      h.goFrom(scenarioStart(h.v), '3-M1');
      expect(hopTypes(h.s.route!), contains('escalator'));
      h.options.setAvoidEscalators(true);
      expect(hopTypes(h.s.route!), isNot(contains('escalator')));
      expect(h.s.needsNote, isNull);
      h.options.setAvoidStairs(true);
      expect(hopTypes(h.s.route!).intersection({'stairs', 'escalator'}), isEmpty);
    });

    test('fallback: Meridian Fashion Hall level 4 is escalator-only, so the route says so', () {
      final h = Harness(mall: 'meridian');
      h.options.setAvoidEscalators(true);
      final f4 = h.v.places.firstWhere((p) => p.lv == 5 && p.wing == 'F' && p.kind == 'store');
      h.goFrom(scenarioStart(h.v), f4.id);
      expect(h.s.route, isNotNull);
      expect(hopTypes(h.s.route!), contains('escalator'));
      expect(h.s.needsNote, 'escalator');
      // elsewhere, no note
      h.nav.startTo(h.v.tripTarget);
      expect(h.s.needsNote, isNull);
    });

    test('an evacuation ignores the preference: stairs are the way out', () {
      final h = Harness();
      h.goFrom(scenarioStart(h.v), '3-M1');
      final steps = stepsOf(h.s.route!);
      h.nav.debugScrub((steps.firstWhere((s) => s.kind == 'hop').endAt + 30) / h.s.route!.total * 1000);
      h.options.setAvoidStairs(true);
      h.options.setAvoidEscalators(true);
      h.nav.startEmergency();
      expect(h.s.route, isNotNull);
      expect(hopTypes(h.s.route!).intersection({'stairs', 'escalator'}), isNotEmpty);
    });
  });

  test('high contrast: text, secondary text and the brand-as-text read at 4.5:1 or better', () {
    for (final dark in [false, true]) {
      final p = Pal.of(dark: dark, hc: true), m = MapPal.of(dark: dark, hc: true);
      expect(contrast(p.ink, p.panel), greaterThan(7), reason: 'ink dark=$dark');
      expect(contrast(p.muted, p.panel), greaterThan(4.5), reason: 'muted dark=$dark');
      expect(contrast(p.muted, p.raised), greaterThan(4.5), reason: 'muted on raised dark=$dark');
      expect(contrast(p.brand2, p.panel), greaterThan(4.5), reason: 'brand text dark=$dark');
      expect(contrast(p.onBrand, p.brand), greaterThan(4.5), reason: 'on the orange dark=$dark');
      expect(contrast(p.line, p.panel), greaterThan(3), reason: 'line dark=$dark');
      for (final (fg, bg) in [(p.open, p.openBg), (p.closed, p.closedBg), (p.maint, p.maintBg), (p.soon, p.soonBg)]) {
        expect(contrast(fg, bg), greaterThan(4.5), reason: 'status dark=$dark');
      }
      expect(contrast(m['text'], m['surface']), greaterThan(7), reason: 'map text dark=$dark');
      expect(contrast(m['muted'], m['surface']), greaterThan(4.5), reason: 'map muted dark=$dark');
      expect(contrast(m['accent-text'], m['surface']), greaterThan(4.5), reason: 'map accent text dark=$dark');
      expect(contrast(m['route-text'], m['surface']), greaterThan(4.5), reason: 'route text dark=$dark');
      expect(contrast(m['label'], m['halo']), greaterThan(7), reason: 'map label dark=$dark');
      expect(contrast(m['outline'], m['surface']), greaterThan(3), reason: 'map outline dark=$dark');
      expect(p.lineW, 2);
      expect(m.line, 2);
    }
    // the normal palettes are LIQo web's
    expect(Pal.light.ink, const Color(0xFF1A1A1F));
    expect(Pal.darkPal.bg, const Color(0xFF121216));
  });

  test('normal palettes: text reads at 4.5:1, status chips too', () {
    for (final p in [Pal.light, Pal.darkPal]) {
      expect(contrast(p.ink, p.panel), greaterThan(7));
      expect(contrast(p.muted, p.panel), greaterThan(4.5));
      for (final (fg, bg) in [(p.open, p.openBg), (p.closed, p.closedBg), (p.maint, p.maintBg), (p.soon, p.soonBg)]) {
        expect(contrast(fg, bg), greaterThan(4.5), reason: 'status dark=${p.dark}');
      }
      for (final t in p.tiles) {
        expect(contrast(Colors.white, t), greaterThan(3), reason: 'initials tile (large bold text)');
      }
    }
  });
}
