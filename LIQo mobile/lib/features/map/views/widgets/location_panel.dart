// "Where are you?": until beacons tell the app (MOKO, later), the shopper says
// where they are. A place near them puts the dot at its door; a floor puts it at
// the floor's centre as an approximate spot they can refine on the map (from the
// demo's location_sheet; the QR code and voice buttons were left out).
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../shared/widgets/common.dart';
import '../../../../shared/widgets/glyphs.dart';
import '../../../navigation/services/location_search.dart';
import 'map_scope.dart';

class LocationPanel extends StatefulWidget {
  const LocationPanel({super.key, this.focus});

  /// Shared with the screen, so the dock can rise above the keyboard while typing.
  final FocusNode? focus;

  @override
  State<LocationPanel> createState() => _LocationPanelState();
}

class _LocationPanelState extends State<LocationPanel> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), s = sc.s, t = sc.t, p = context.pal;
    if (_ctl.text != s.locQuery) _ctl.text = s.locQuery;
    final res = locationResults(s, s.locQuery);
    final subtitle = s.emergency
        ? sc.tr('Tell us where you are, and the way out will show.')
        : s.locDrift
            ? sc.tr("Looks like you've drifted off the way. Let's start again from here.")
            : s.pendingPlace != null
                ? sc.tr('Tell us where you are, and the way there will show.')
                : sc.tr('Indoor positioning can be off, so tell us: a shop near you, or your floor.');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Grab(),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const Tile('i-pin', size: 48),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sc.tr('Where are you?'), style: ts(18, w: FontWeight.w700, color: p.ink)),
              Text(subtitle, style: ts(12.5, color: p.muted)),
            ]),
          ),
          const SizedBox(width: 10),
          RoundBtn('i-close', label: sc.tr('Close'), onTap: () {
            widget.focus?.unfocus();
            sc.nav.closeLocation();
          }),
        ]),
      ),
      Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line, width: p.lineW)),
        child: Row(children: [
          AppIcon('i-search', size: 18, color: p.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('loc-search'),
              controller: _ctl,
              focusNode: widget.focus,
              onChanged: sc.nav.setLocQuery,
              autocorrect: false,
              enableSuggestions: false,
              style: ts(15, color: p.ink),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: sc.tr('Type a shop, or describe where you are'),
                hintStyle: ts(15, color: p.muted),
                hintMaxLines: 1,
              ),
            ),
          ),
        ]),
      ),
      if (res.places.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CardX(children: [
            for (var i = 0; i < res.places.length; i++)
              RowX(
                key: ValueKey('loc-${res.places[i].id}'),
                onTap: () {
                  widget.focus?.unfocus();
                  sc.nav.locAtPlace(res.places[i].id);
                },
                lead: CatTile(res.places[i].cat),
                title: res.places[i].name,
                sub: [
                  t.placeSub(res.places[i]),
                  if (res.near[res.places[i].id] != null) sc.tr('near ${res.near[res.places[i].id]}'),
                  sc.tr("I'm near here"),
                ].join(' · '),
                last: i == res.places.length - 1,
              ),
          ]),
        )
      else if (s.locQuery.trim().isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(sc.tr('Nothing found. Try another name, or pick your floor.'), style: ts(13, color: p.muted))),
      SectionLabel(sc.tr('OR PICK YOUR FLOOR'), padding: const EdgeInsets.only(top: 14, bottom: 6)),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final lv in s.levelsDesc.reversed)
          Semantics(
            button: true,
            label: s.levels[lv].name,
            child: Tap(
              onTap: () {
                widget.focus?.unfocus();
                sc.nav.locAtFloor(lv);
              },
              child: Container(
                key: ValueKey('locfloor-$lv'),
                constraints: const BoxConstraints(minWidth: 44),
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: lv == s.user?.lv ? p.soft : p.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: lv == s.user?.lv ? p.brand : p.line, width: p.lineW),
                ),
                // sized to its label: a Container with an alignment would stretch across the Wrap
                child: Center(widthFactor: 1, child: Text(s.levels[lv].short, style: ts(14, w: FontWeight.w700, color: lv == s.user?.lv ? p.brand2 : p.ink))),
              ),
            ),
          ),
      ]),
      btns([
        Btn(
          s.hasPosition ? sc.tr('Skip · keep my last spot') : sc.tr('Skip for now'),
          onTap: () {
            widget.focus?.unfocus();
            sc.nav.closeLocation();
          },
          height: 42,
          fontSize: 14,
        ),
      ]),
    ]);
  }
}

/// The sheet's grab handle.
class Grab extends StatelessWidget {
  const Grab({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: context.pal.line, borderRadius: BorderRadius.circular(2)),
        ),
      );
}
