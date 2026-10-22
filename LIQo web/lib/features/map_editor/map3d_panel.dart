import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/widgets/common.dart';
import 'editor_state.dart';
import 'map3d_host.dart';
import 'map_canvas.dart';
import 'maps_service.dart';

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Proposal in the JSON shape of the map document, for the 3D preview.
Map<String, dynamic> proposalJson(Proposal p) => {
      'levelId': p.levelId,
      'walls': p.walls.map((w) => w.toJson()).toList(),
      'openings': p.openings.map((o) => o.toJson()).toList(),
      'spaces': p.spaces.map((s) => s.toJson()).toList(),
      if (p.outline != null) 'outline': p.outline!.toJson(),
      'uncertain': p.uncertain.toList(),
    };

/// What the 3D preview draws (Round 17, US-036): the whole document with every
/// level, the current level, the AI proposal, the pieces named in warnings, the
/// catalog sizes of features, and the theme's colours.
Map<String, dynamic> map3dPayload(EditorData st, Pal p) => {
      'doc': st.doc?.toJson(),
      'levelId': st.levelId,
      'proposal': st.proposal == null ? null : proposalJson(st.proposal!),
      // A new proposal (not an edit of the same one) makes its walls rise in.
      'proposalKey': st.proposal == null ? null : '${identityHashCode(st.proposal)}:${st.proposal!.sections}',
      'problems': [for (final w in st.warnings) ...w.ids],
      'featureSizes': {for (final e in (st.catalog?.features ?? const <String, FeatureDef>{}).entries) e.key: e.value.size},
      'colors': {
        'background': _hex(p.bg),
        'wall': _hex(p.pick(const Color(0xFF3A3A44), const Color(0xFFD9D9E0))),
        'boundary': _hex(p.ink),
        'glass': _hex(p.pick(const Color(0xFF7CC7E8), const Color(0xFF5BB4DA))),
        'slab': _hex(p.panel),
        'label': _hex(p.ink),
        'labelBg': _hex(p.panel),
        'feature': _hex(p.brand),
        'connector': _hex(p.brand2),
        'proposal': _hex(p.aiProposal),
        'unsure': _hex(p.aiUnsure),
        'problem': _hex(p.danger),
        // Round 18 (nicer 3D): door frames, entrances, room edges and wall edge lines.
        'frame': _hex(p.slate),
        'entrance': _hex(p.brand),
        'roomEdge': _hex(p.panel),
        'wallEdge': _hex(p.ink),
        'rooms': {for (final e in spaceTypeColors.entries) e.key: _hex(e.value.withValues(alpha: 1))},
      },
    };

/// The 3D preview beside the 2D canvas. Preview only: editing stays in 2D.
class Map3dPanel extends ConsumerStatefulWidget {
  const Map3dPanel({super.key, required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  ConsumerState<Map3dPanel> createState() => _Map3dPanelState();
}

class _Map3dPanelState extends ConsumerState<Map3dPanel> {
  final _reset = Map3dReset();
  String _payload = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Edits arrive quickly while dragging; the scene follows at most every 150 ms.
  void _schedule(String next) {
    if (next == _payload) return;
    if (_payload.isEmpty) {
      _payload = next;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _payload = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = ref.watch(editorProvider);
    _schedule(jsonEncode(map3dPayload(st, p)));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                Icon(Icons.view_in_ar_outlined, size: 16, color: p.brand2),
                const SizedBox(width: 6),
                Expanded(child: Text('3D preview', style: ts(12, w: FontWeight.w700, color: p.ink), overflow: TextOverflow.ellipsis)),
                IconButton(tooltip: 'Reset view', iconSize: 18, visualDensity: VisualDensity.compact, icon: Icon(Icons.center_focus_strong_outlined, color: p.slate), onPressed: _reset.fire),
                IconButton(tooltip: 'Collapse', iconSize: 18, visualDensity: VisualDensity.compact, icon: Icon(Icons.chevron_right, color: p.slate), onPressed: widget.onCollapse),
              ],
            ),
          ),
          Divider(height: 1, color: p.softLine),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: Map3dHost(payload: _payload, reset: _reset),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Text('Drag to turn · wheel to zoom · right-drag to slide', style: ts(10, color: p.sideNote), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// The slim strip left when the 3D preview is collapsed.
class Map3dCollapsed extends StatelessWidget {
  const Map3dCollapsed({super.key, required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      child: InkWell(
        onTap: onExpand,
        borderRadius: BorderRadius.circular(14),
        child: Center(
          child: RotatedBox(
            quarterTurns: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.view_in_ar_outlined, size: 15, color: p.brand2),
                const SizedBox(width: 6),
                Text('3D preview', style: ts(11, w: FontWeight.w700, color: p.slate)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
