// The question the walk is asking, as a pop-up the shopper cannot miss: the
// ride check ("Are you at West Court escalators?"), the pause check ("Are you
// here?") or the arrival ("I've arrived"). The scrim takes the taps.
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../shared/widgets/common.dart';
import '../../../../shared/widgets/glyphs.dart';
import '../../../navigation/services/narration.dart';
import 'map_scope.dart';

class PromptOverlay extends StatelessWidget {
  const PromptOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), s = sc.s, t = sc.t, p = context.pal, kind = s.prompt!;
    final String title, body;
    if (kind == 'end') {
      title = sc.tr('Have you arrived?');
      body = t.atEndSentence();
    } else {
      // "Are you here? You should be on level 2, with Zen Gifts ahead. If that's right, ..."
      final q = t.checkQuestion(), cut = q.indexOf('? ');
      title = cut < 0 ? q : q.substring(0, cut + 1);
      body = cut < 0 ? '' : q.substring(cut + 2);
    }
    final yes = switch (kind) {
      'ride' => Btn(sc.tr("Yes, I'm here"), primary: true, fontSize: 14, onTap: sc.nav.answerYes),
      'here' => Btn(sc.tr("Yes, that's right"), fontSize: 14, onTap: sc.nav.answerYes),
      _ => Btn(sc.tr("I've arrived"), primary: true, fontSize: 14, onTap: sc.nav.confirmArrived),
    };
    final ride = s.checkRideIndex;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // the map waits for the answer
      child: Container(
        color: p.scrim,
        alignment: Alignment.center,
        padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 24, 24, 24),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 360, maxHeight: MediaQuery.sizeOf(context).height * .8),
            child: Container(
              key: const ValueKey('prompt'),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              decoration: cardDeco(p, 20),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: AppIcon(kind == 'end' ? 'i-flag' : ride != null ? 'g-${s.directions[ride].type}' : 'i-pin', size: 20, color: p.onBrand),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(title, style: ts(17, w: FontWeight.w800, color: p.ink))),
                  ]),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(body, style: ts(14.5, w: FontWeight.w500, color: p.ink)),
                  ],
                  btns([yes, Btn(sc.tr("No, I'm somewhere else"), primary: kind == 'here', fontSize: 14, onTap: sc.nav.answerNo)], top: 14),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
