import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../../../shared/forms/field_builder.dart';
import '../../../shared/forms/field_spec.dart';
import '../../../shared/messaging/messages.dart';
import '../../../shared/models/paged.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../ai/ai_service.dart';
import '../../ai/my_credits.dart';
import '../../ai/credits_service.dart';
import '../../stores/stores_service.dart';
import '../ai_scan_dialog.dart';
import '../blueprint_panel.dart';
import '../editor_state.dart';
import '../map_models.dart';
import '../maps_service.dart';
import '../plan_upload.dart';

// The easy editor (Round 18, owner decision 2026-10-22): guided steps that
// anyone can follow — ① Plan ② Scale ③ Read with AI ④ Rooms ⑤ Publish — with
// one short hint each, plain words, and every change one Undo away. The full
// tools stay under "Advanced editing".

const guidedSteps = ['Plan', 'Scale', 'Read with AI', 'Rooms', 'Publish'];

/// Room types in plain words (the "custom" type needs a typed name, so it stays in Advanced).
const roomTypeWords = <String, String>{
  'retail': 'Shop',
  'food': 'Food & drink',
  'anchor': 'Big store',
  'service': 'Service',
  'office': 'Office',
  'storage': 'Storage',
  'atrium': 'Open area',
  'corridor': 'Walkway',
  'restroom': 'Restroom',
  'parking': 'Parking',
  'outdoor': 'Outdoor',
};

/// The branch's stores, for linking them to rooms.
final branchStoresProvider = FutureProvider.autoDispose.family<List<Store>, int>((ref, branchId) async {
  final page = await StoresService().list(ListQuery(pageSize: 100, filters: {'branchId': '$branchId', 'status': 'active'}));
  return page.items;
});

/// The step bar above the editor: the five steps, Undo and Redo, and the way
/// to the full tools.
class GuidedStepBar extends ConsumerWidget {
  const GuidedStepBar({super.key, required this.onAdvanced});

  final VoidCallback onAdvanced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final st = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (i, name) in guidedSteps.indexed) _StepChip(index: i, label: name, active: st.guidedStep == i, done: st.guidedStep > i, onTap: () => n.setGuidedStep(i)),
          const SizedBox(width: 10),
          AppButton(key: const ValueKey('guided-undo'), label: 'Undo', small: true, icon: Icons.undo, onPressed: st.undoDepth > 0 ? n.undo : () {}),
          AppButton(key: const ValueKey('guided-redo'), label: 'Redo', small: true, icon: Icons.redo, onPressed: st.redoDepth > 0 ? n.redo : () {}),
          TextButton(
            key: const ValueKey('guided-advanced'),
            onPressed: onAdvanced,
            child: Text('Advanced editing', style: ts(12, w: FontWeight.w700, color: p.brand2)),
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.index, required this.label, required this.active, required this.done, required this.onTap});

  final int index;
  final String label;
  final bool active;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      key: ValueKey('guided-step-$index'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? p.soft : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? p.brand : p.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: active || done ? p.brand : p.fieldLine),
              child: done ? const Icon(Icons.check, size: 13, color: Colors.white) : Text('${index + 1}', style: ts(11, w: FontWeight.w800, color: active ? Colors.white : p.muted)),
            ),
            const SizedBox(width: 6),
            Text(label, style: ts(12, w: FontWeight.w700, color: active ? p.brand2 : p.slate)),
          ],
        ),
      ),
    );
  }
}

/// The right-hand panel of the easy editor: only what the current step needs.
class GuidedPanel extends ConsumerWidget {
  const GuidedPanel({super.key, required this.onPublish});

  final Future<void> Function() onPublish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final step = st.guidedStep;
    final body = switch (step) {
      0 => const _PlanStep(),
      1 => const _ScaleStep(),
      2 => const _ReadStep(),
      3 => const _RoomsStep(),
      _ => _PublishStep(onPublish: onPublish),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: body)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (step > 0) AppButton(key: const ValueKey('guided-back'), label: 'Back', icon: Icons.arrow_back, onPressed: () => n.setGuidedStep(step - 1)),
              if (step < 4) AppButton(key: const ValueKey('guided-next'), label: 'Next', icon: Icons.arrow_forward, primary: true, onPressed: () => n.setGuidedStep(step + 1)),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _title(BuildContext context, String number, String title, String hint) {
  final p = context.pal;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('STEP $number', style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1)),
      const SizedBox(height: 2),
      Text(title, style: ts(16, w: FontWeight.w800, color: p.ink)),
      const SizedBox(height: 4),
      Text(hint, style: ts(12, color: p.muted)),
      const SizedBox(height: 14),
    ],
  );
}

void _say(WidgetRef ref, String text, {bool error = false}) {
  final m = ref.read(messagesProvider.notifier);
  error ? m.showError(text) : m.showSuccess(text);
}

// ---- ① Plan ----

class _PlanStep extends ConsumerStatefulWidget {
  const _PlanStep();

  @override
  ConsumerState<_PlanStep> createState() => _PlanStepState();
}

class _PlanStepState extends ConsumerState<_PlanStep> {
  String? _busy;

  Future<void> _replace() async {
    final st = ref.read(editorProvider);
    final branchId = st.branchId;
    if (branchId == null) return;
    final up = PlanUpload(context, ref, onBusy: (l) {
      if (mounted) setState(() => _busy = l);
    });
    try {
      final uploaded = await up.pickAndUpload(branchId);
      if (uploaded == null) return;
      final info = await up.resolveUnit(branchId, uploaded);
      if (info == null) return;
      final n = ref.read(editorProvider.notifier);
      n.placeBackdrop(info);
      n.requestFit();
      _say(ref, 'Plan placed. Next: check its scale.');
    } catch (e) {
      _say(ref, formatApiError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = ref.watch(editorProvider);
    final bd = st.level?.backdrop;
    final uploads = st.branchId == null ? null : ref.watch(backdropsProvider(st.branchId!)).valueOrNull;
    final info = bd == null ? null : uploads?.cast<BackdropInfo?>().firstWhere((u) => u!.id == bd.id, orElse: () => null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(context, '1', 'Your floor plan', 'The plan sits under the map so the walls and rooms can be read from it.'),
        if (bd == null)
          Text('No plan on this floor yet.', style: ts(13, color: p.ink))
        else
          Text(info == null ? 'A plan is on this floor.' : '${info.originalName ?? 'Plan'} · ${info.isDrawing ? '${info.kind.toUpperCase()} drawing' : '${info.width} × ${info.height} px'}',
              style: ts(13, color: p.ink)),
        const SizedBox(height: 12),
        if (st.editable)
          AppButton(
            key: const ValueKey('guided-upload'),
            label: _busy ?? (bd == null ? 'Upload a floor plan' : 'Use another plan'),
            icon: Icons.upload_file,
            primary: bd == null,
            onPressed: _busy == null ? _replace : () {},
          ),
        const SizedBox(height: 10),
        Text('Pictures, PDF, SVG, DXF and DWG are all fine.', style: ts(11, color: p.sideNote)),
      ],
    );
  }
}

// ---- ② Scale ----

class _ScaleStep extends ConsumerStatefulWidget {
  const _ScaleStep();

  @override
  ConsumerState<_ScaleStep> createState() => _ScaleStepState();
}

class _ScaleStepState extends ConsumerState<_ScaleStep> {
  Object? _metres;

  void _apply() {
    final v = double.tryParse('${_metres ?? ''}'.trim());
    if (v == null || v <= 0) {
      _say(ref, 'Type how long that distance really is, in metres.', error: true);
      return;
    }
    final err = ref.read(editorProvider.notifier).applyCalibration(v);
    if (err != null) {
      _say(ref, err, error: true);
    } else {
      setState(() => _metres = null);
      _say(ref, 'Scale set.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final bd = st.level?.backdrop;
    final children = <Widget>[
      _title(context, '2', 'The plan\'s real size', 'Sizes must be right for the map to be right. If the plan has a written measurement (like 11070), the AI uses it automatically when it reads.'),
    ];
    if (bd == null) {
      children.add(Text('Add a plan first (step 1).', style: ts(13, color: p.ink)));
    } else if (st.calibrating) {
      final pts = st.calibPoints.length;
      children.addAll([
        Text(
          pts == 0
              ? 'Click the START of a length you know on the plan (for example one end of a written dimension).'
              : pts == 1
                  ? 'Now click its END.'
                  : 'How long is it really?',
          key: const ValueKey('guided-calib-hint'),
          style: ts(13, w: FontWeight.w700, color: p.brand2),
        ),
        const SizedBox(height: 10),
        if (pts == 2) ...[
          FieldBuilder(
            spec: const FieldSpec(name: 'metres', label: 'Real length (metres)', kind: FieldKind.decimal, required: true, min: 0.1, max: 2000, hint: 'e.g. 11.07'),
            value: _metres,
            onChanged: (v) => setState(() => _metres = v),
          ),
          AppButton(key: const ValueKey('guided-calib-apply'), label: 'Set the scale', primary: true, onPressed: _apply),
          const SizedBox(height: 8),
        ],
        AppButton(label: 'Cancel', onPressed: n.cancelCalibration),
      ]);
    } else {
      children.addAll([
        Row(
          children: [
            Icon(bd.calibrated ? Icons.check_circle : Icons.info_outline, color: bd.calibrated ? p.green : p.warn, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                bd.calibrated ? 'The scale is set.' : 'The scale is not set yet. The AI will try to find it from a written measurement; you can also set it yourself.',
                key: const ValueKey('guided-scale-state'),
                style: ts(13, color: p.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (st.editable) AppButton(key: const ValueKey('guided-calib-start'), label: bd.calibrated ? 'Set it again' : 'Set it myself', icon: Icons.straighten, onPressed: n.startCalibration),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

// ---- ③ Read with AI ----

class _ReadStep extends ConsumerWidget {
  const _ReadStep();

  Future<void> _read(BuildContext context, WidgetRef ref) async {
    final st = ref.read(editorProvider);
    final bd = st.level?.backdrop;
    final work = ref.read(editorProvider.notifier).convertBackdrop();
    final scan = bd != null && st.branchId != null ? showAiScan(context, done: work, branchId: st.branchId!, backdropKey: bd.id) : null;
    final err = await work;
    ref.invalidate(aiStatusProvider);
    ref.invalidate(myCreditsProvider);
    if (err != null) {
      if (scan == null) {
        _say(ref, err, error: true);
      } else if (await scan && context.mounted) {
        await _read(context, ref);
      }
      return;
    }
    final found = ref.read(editorProvider).proposal?.scaleFound;
    if (found != null) _say(ref, 'The plan\'s size was found from the measurement ${found.mm} mm written on it.');
  }

  Future<void> _add(WidgetRef ref) async {
    final st = ref.read(editorProvider);
    final p = st.proposal;
    if (p == null) return;
    final err = await ref.read(editorProvider.notifier).acceptProposal(outline: st.level?.outline == null || p.outline != null, linkStores: p.storeMatches.isNotEmpty);
    if (err != null) {
      _say(ref, err, error: true);
    } else {
      ref.read(editorProvider.notifier).setGuidedStep(3);
      _say(ref, 'Added to the map. Undo takes it all back in one step. Next: check the rooms.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final st = ref.watch(editorProvider);
    final status = ref.watch(aiStatusProvider);
    final prop = st.proposal != null && st.proposal!.levelId == st.levelId ? st.proposal : null;
    final ready = status.valueOrNull?.ready ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(context, '3', 'Let the AI read the plan', 'It finds the walls, doors and rooms with their names. Nothing is added until you say so.'),
        status.when(
          loading: () => const Shimmer(child: SkeletonLines(widths: [0.8, 0.5], height: 9)),
          error: (e, _) => Text(formatApiError(e), style: ts(12, color: p.warn)),
          // Round 19: a mall admin sees their own credits (and can ask for more); a superadmin the wallet.
          data: (s) => s.blocker != null && !s.outOfCredits ? Text(s.blocker!, style: ts(12, color: p.warn)) : AiReadingCredits(status: s),
        ),
        const SizedBox(height: 12),
        if (st.level?.backdrop == null)
          Text('Add a plan first (step 1).', style: ts(13, color: p.ink))
        else if (prop == null && st.editable)
          AppButton(
            key: const ValueKey('guided-read'),
            label: st.converting ? 'Reading…' : 'Read with AI',
            icon: Icons.auto_awesome,
            primary: true,
            onPressed: st.converting || !ready ? () {} : () => _read(context, ref),
          ),
        if (prop != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.aiProposalPanel, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.aiProposal)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('The AI found', style: ts(13, w: FontWeight.w800, color: p.aiProposal)),
                const SizedBox(height: 4),
                Text(
                  '${prop.spaces.length} rooms (${prop.spaces.where((s) => s.name.isNotEmpty).length} with names) · ${prop.walls.length} walls · ${prop.openings.length} doors',
                  key: const ValueKey('guided-found'),
                  style: ts(12, color: p.ink),
                ),
                if (prop.uncertain.isNotEmpty) Text('${prop.uncertain.length} pieces it was unsure of are dashed in amber.', style: ts(12, color: p.aiUnsure)),
                for (final note in prop.notes.take(3)) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note, style: ts(11, color: p.muted))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (st.editable)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(key: const ValueKey('guided-add'), label: 'Add to the map', icon: Icons.check, primary: true, onPressed: () => _add(ref)),
                AppButton(key: const ValueKey('guided-discard'), label: 'Discard', onPressed: ref.read(editorProvider.notifier).discardProposal),
              ],
            ),
        ],
      ],
    );
  }
}

// ---- ④ Rooms ----

class _RoomsStep extends ConsumerStatefulWidget {
  const _RoomsStep();

  @override
  ConsumerState<_RoomsStep> createState() => _RoomsStepState();
}

class _RoomsStepState extends ConsumerState<_RoomsStep> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final level = st.level;
    if (level == null) return const SizedBox.shrink();
    final sel = st.selection;
    final children = <Widget>[
      _title(context, '4', 'Check the rooms', 'Click a room on the map (or in the list) to name it, set its type or link its store. Drag the map to move around.'),
    ];
    if (st.editable) children.add(_Tools(st: st, n: n));
    children.add(const SizedBox(height: 14));
    if (sel.kind == SelKind.space) {
      final room = level.spaces.cast<Space?>().firstWhere((s) => s!.id == sel.id, orElse: () => null);
      if (room != null) children.add(_RoomCard(room: room, st: st));
    } else if (sel.kind == SelKind.wall) {
      final w = level.wallById(sel.id);
      if (w != null) {
        children.add(_PieceCard(title: 'Wall · ${w.length.toStringAsFixed(1)} m', hint: 'Drag one of its round ends to adjust it.', st: st, extra: [
          AppButton(label: 'Add a door here', small: true, icon: Icons.door_front_door_outlined, onPressed: () => n.setGuidedTool(GuidedTool.addDoor)),
        ]));
      }
    } else if (sel.kind == SelKind.opening) {
      final o = level.openings.cast<Opening?>().firstWhere((x) => x!.id == sel.id, orElse: () => null);
      if (o != null) {
        children.add(_PieceCard(
            title: '${o.kind == 'entrance' ? 'Entrance' : o.kind == 'shutter' ? 'Shop front' : 'Door'} · ${o.w.toStringAsFixed(1)} m',
            hint: '',
            st: st));
      }
    } else if (!sel.isEmpty) {
      children.add(_PieceCard(title: 'Selected', hint: '', st: st));
    }
    children.addAll([
      const SizedBox(height: 14),
      FieldBuilder(
        spec: const FieldSpec(name: 'search', label: 'Find a room or store', hint: 'Type a name'),
        value: _search,
        onChanged: (v) => setState(() => _search = '${v ?? ''}'.trim().toLowerCase()),
      ),
      _RoomList(level: level, st: st, search: _search),
      if (st.branchId != null) _StoreList(branchId: st.branchId!, st: st, search: _search),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _Tools extends StatelessWidget {
  const _Tools({required this.st, required this.n});

  final EditorData st;
  final EditorNotifier n;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final t = st.guidedTool;
    Widget tool(String label, IconData icon, GuidedTool which, {VoidCallback? on}) => AppButton(
          key: ValueKey('guided-tool-${which.name}'),
          label: label,
          small: true,
          icon: icon,
          primary: t == which,
          onPressed: on ?? () => t == which ? n.cancelGuidedTool() : n.setGuidedTool(which),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('FIX THE MAP', style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            tool('Add wall', Icons.horizontal_rule, GuidedTool.addWall),
            tool('Add door', Icons.door_front_door_outlined, GuidedTool.addDoor),
            tool('Split a room', Icons.call_split, GuidedTool.split),
          ],
        ),
        if (t == GuidedTool.addDoor) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in doorPresets.keys)
                ChoiceChip(
                  key: ValueKey('door-preset-$name'),
                  label: Text('$name ${doorPresets[name]!.$2.toStringAsFixed(1)} m', style: ts(11, color: st.doorPreset == name ? p.brand2 : p.ink)),
                  selected: st.doorPreset == name,
                  showCheckmark: false,
                  selectedColor: p.soft,
                  backgroundColor: p.panel,
                  side: BorderSide(color: st.doorPreset == name ? p.brand : p.line),
                  onSelected: (_) => n.setDoorPreset(name),
                ),
            ],
          ),
        ],
        if (t != GuidedTool.none) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Follow the hint on the map. Esc cancels.', style: ts(11, color: p.brand2))),
      ],
    );
  }
}

class _PieceCard extends StatelessWidget {
  const _PieceCard({required this.title, required this.hint, required this.st, this.extra = const []});

  final String title;
  final String hint;
  final EditorData st;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Consumer(
      builder: (context, ref, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.boxBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, key: const ValueKey('guided-piece'), style: ts(13, w: FontWeight.w800, color: p.ink)),
            if (hint.isNotEmpty) Text(hint, style: ts(11, color: p.muted)),
            const SizedBox(height: 8),
            if (st.editable)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...extra,
                  AppButton(
                    key: const ValueKey('guided-remove'),
                    label: 'Remove',
                    small: true,
                    icon: Icons.delete_outline,
                    onPressed: () {
                      ref.read(editorProvider.notifier).deleteSelection();
                      _say(ref, 'Removed. Undo (at the top) brings it back.');
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends ConsumerStatefulWidget {
  const _RoomCard({required this.room, required this.st});

  final Space room;
  final EditorData st;

  @override
  ConsumerState<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends ConsumerState<_RoomCard> {
  Object? _name;

  @override
  void didUpdateWidget(covariant _RoomCard old) {
    super.didUpdateWidget(old);
    if (old.room.id != widget.room.id) _name = null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final room = widget.room;
    final st = widget.st;
    final n = ref.read(editorProvider.notifier);
    final links = st.storeLinks.where((l) => l.spaceKey == room.id).map((l) => l.storeName).toList();
    final ro = !st.editable;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.boxBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(room.name.isEmpty ? 'Room without a name' : room.name, key: const ValueKey('guided-room-title'), style: ts(14, w: FontWeight.w800, color: p.ink)),
          Text('${room.shape.area.toStringAsFixed(1)} m²${links.isEmpty ? '' : ' · ${links.join(', ')}'}', style: ts(11, color: p.muted)),
          const SizedBox(height: 10),
          FieldBuilder(
            key: ValueKey('room-name-${room.id}'),
            spec: FieldSpec(name: 'name', label: 'Name', maxLength: 80, hint: 'e.g. Starbucks', readOnly: ro),
            value: _name ?? room.name,
            onChanged: (v) => setState(() => _name = v),
          ),
          if (!ro && _name != null && '$_name'.trim() != room.name)
            AppButton(
              key: const ValueKey('guided-save-name'),
              label: 'Save name',
              small: true,
              primary: true,
              onPressed: () {
                n.renameSpace(room.id, '$_name');
                setState(() => _name = null);
              },
            ),
          FieldBuilder(
            key: ValueKey('room-type-${room.id}'),
            spec: FieldSpec(
              name: 'type',
              label: 'Type',
              kind: FieldKind.select,
              readOnly: ro,
              options: [for (final e in roomTypeWords.entries) SelectOption(e.key, e.value)],
            ),
            value: roomTypeWords.containsKey(room.type) ? room.type : null,
            onChanged: (v) {
              if (v is String) n.setSpaceType(room.id, v);
            },
          ),
          if (!ro) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AppButton(key: const ValueKey('guided-merge'), label: 'Join with a room next to it', small: true, icon: Icons.merge_type, onPressed: () => n.setGuidedTool(GuidedTool.merge)),
                AppButton(key: const ValueKey('guided-split'), label: 'Split in two', small: true, icon: Icons.call_split, onPressed: () => n.setGuidedTool(GuidedTool.split)),
                AppButton(
                  key: const ValueKey('guided-remove-room'),
                  label: 'Remove',
                  small: true,
                  icon: Icons.delete_outline,
                  onPressed: () {
                    n.deleteSelection();
                    _say(ref, 'Room removed. Undo (at the top) brings it back.');
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RoomList extends ConsumerWidget {
  const _RoomList({required this.level, required this.st, required this.search});

  final Level level;
  final EditorData st;
  final String search;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final n = ref.read(editorProvider.notifier);
    final rooms = level.spaces.where((s) => search.isEmpty || s.name.toLowerCase().contains(search)).toList()
      ..sort((a, b) => (a.name.isEmpty ? 'zzz' : a.name.toLowerCase()).compareTo(b.name.isEmpty ? 'zzz' : b.name.toLowerCase()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('ROOMS (${level.spaces.length})', style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1)),
        if (rooms.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(level.spaces.isEmpty ? 'No rooms yet. Read the plan with AI (step 3).' : 'No room matches.', style: ts(12, color: p.muted))),
        for (final r in rooms.take(80))
          InkWell(
            key: ValueKey('guided-room-${r.id}'),
            onTap: () => n.select(Selection(SelKind.space, r.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.crop_square, size: 14, color: st.selection.id == r.id ? p.brand : p.slate),
                  const SizedBox(width: 6),
                  Expanded(child: Text(r.name.isEmpty ? 'Room without a name' : r.name, style: ts(12, color: r.name.isEmpty ? p.muted : p.ink), overflow: TextOverflow.ellipsis)),
                  Flexible(child: Text(roomTypeWords[r.type] ?? r.type, style: ts(11, color: p.sideNote), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StoreList extends ConsumerWidget {
  const _StoreList({required this.branchId, required this.st, required this.search});

  final int branchId;
  final EditorData st;
  final String search;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final n = ref.read(editorProvider.notifier);
    final stores = ref.watch(branchStoresProvider(branchId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text('STORES', style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1)),
        stores.when(
          loading: () => const Shimmer(child: SkeletonLines(widths: [0.7, 0.5, 0.6], height: 9)),
          error: (e, _) => Text(formatApiError(e), style: ts(12, color: p.warn)),
          data: (items) {
            final shown = items.where((s) => search.isEmpty || s.name.toLowerCase().contains(search)).toList();
            if (shown.isEmpty) {
              return Padding(padding: const EdgeInsets.only(top: 6), child: Text(items.isEmpty ? 'No stores in this branch yet.' : 'No store matches.', style: ts(12, color: p.muted)));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in shown.take(80))
                  Builder(builder: (context) {
                    final linked = st.storeLinks.where((l) => l.storeId == s.id).toList();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.storefront_outlined, size: 14, color: linked.isEmpty ? p.slate : p.green),
                          const SizedBox(width: 6),
                          Expanded(child: Text(s.name, style: ts(12, color: p.ink), overflow: TextOverflow.ellipsis)),
                          if (linked.isNotEmpty)
                            Flexible(
                              child: AppButton(
                                key: ValueKey('guided-find-store-${s.id}'),
                                label: 'Show',
                                small: true,
                                onPressed: () => n.selectById(linked.first.spaceKey),
                              ),
                            )
                          else if (st.editable)
                            Flexible(
                              child: AppButton(
                                key: ValueKey('guided-place-store-${s.id}'),
                                label: 'Place on map',
                                small: true,
                                primary: st.pickStore?.storeId == s.id,
                                onPressed: () => n.startPlacingStore(StoreLink(spaceKey: '', storeId: s.id, storeName: s.name)),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---- ⑤ Publish ----

class _PublishStep extends ConsumerWidget {
  const _PublishStep({required this.onPublish});

  final Future<void> Function() onPublish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final st = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final level = st.level;
    final unnamed = level?.spaces.where((s) => s.name.isEmpty).toList() ?? const <Space>[];
    final checks = <(String, VoidCallback?)>[
      if (level?.backdrop == null && (level?.walls.isEmpty ?? true)) ('This floor has no plan and no walls yet.', () => n.setGuidedStep(0)),
      if (unnamed.isNotEmpty)
        (
          '${unnamed.length} ${unnamed.length == 1 ? 'room has' : 'rooms have'} no name.',
          () {
            n.setGuidedStep(3);
            n.select(Selection(SelKind.space, unnamed.first.id));
          }
        ),
      for (final w in st.warnings.take(8)) (w.message, w.ids.isEmpty ? null : () => n.selectById(w.ids.first)),
      for (final pr in st.publishProblems.take(5)) (pr, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(context, '5', 'Make it live', 'Publishing makes this map the one shoppers see. You can keep editing afterwards and publish again.'),
        if (checks.isEmpty)
          Row(children: [Icon(Icons.check_circle, color: p.green, size: 18), const SizedBox(width: 8), Expanded(child: Text('Everything looks ready.', style: ts(13, color: p.ink)))])
        else ...[
          Text('Worth a look first:', style: ts(12, w: FontWeight.w700, color: p.ink)),
          const SizedBox(height: 6),
          for (final (i, (text, on)) in checks.indexed)
            InkWell(
              key: ValueKey('guided-check-$i'),
              onTap: on,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.radio_button_unchecked, size: 14, color: p.warn),
                    const SizedBox(width: 6),
                    Expanded(child: Text(text, style: ts(12, color: on == null ? p.ink : p.brand2))),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 14),
        if (st.editable) AppButton(key: const ValueKey('guided-publish'), label: 'Publish the map', icon: Icons.publish_outlined, primary: true, onPressed: () => unawaited(onPublish())),
      ],
    );
  }
}
