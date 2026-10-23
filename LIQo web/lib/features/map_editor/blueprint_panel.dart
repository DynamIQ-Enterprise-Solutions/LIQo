import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_builder.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import '../ai/ai_service.dart';
import '../ai/credit_bar.dart';
import '../ai/my_credits.dart';
import '../ai/credits_service.dart';
import 'ai_scan_dialog.dart';
import 'editor_state.dart';
import 'maps_service.dart';
import 'pdf_document.dart';
import 'plan_upload.dart';

final backdropsProvider = FutureProvider.autoDispose.family<List<BackdropInfo>, int>((ref, branchId) => MapsService().backdrops(branchId));

/// Upload a floor plan (picture or PDF page), place it under the level,
/// calibrate its scale, and read it with AI into a reviewable proposal.
class BlueprintPanel extends ConsumerStatefulWidget {
  const BlueprintPanel({super.key});

  @override
  ConsumerState<BlueprintPanel> createState() => _BlueprintPanelState();
}

class _BlueprintPanelState extends ConsumerState<BlueprintPanel> {
  String? _busyLabel;
  final _metres = TextEditingController();
  bool _incWalls = true;
  bool _incDoors = true;
  bool _incSpaces = true;
  bool? _incOutline;
  bool _linkStores = true;

  @override
  void dispose() {
    _metres.dispose();
    super.dispose();
  }

  void _msg(String text, {bool error = false}) {
    final m = ref.read(messagesProvider.notifier);
    error ? m.showError(text) : m.showSuccess(text);
  }

  /// Upload a plan (Round 16 formats): PDF → a page as PNG; TIFF, WebP, BMP, GIF
  /// and HEIC → PNG in the browser; SVG, DXF and DWG go up as they are and the
  /// server draws them. A DXF or DWG without a unit asks for one before placing.
  PlanUpload get _uploader => PlanUpload(context, ref, onBusy: (label) {
        if (mounted) setState(() => _busyLabel = label);
      });

  Future<void> _upload() async {
    final branchId = ref.read(editorProvider).branchId;
    if (branchId == null) return;
    try {
      final info = await _uploader.pickAndUpload(branchId);
      if (info != null) await _place(info);
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _placeSafely(BackdropInfo u) async {
    try {
      await _place(u);
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  /// Places an upload; a drawing without a unit asks for it first.
  Future<void> _place(BackdropInfo upload) async {
    final branchId = ref.read(editorProvider).branchId;
    if (branchId == null) return;
    final info = await _uploader.resolveUnit(branchId, upload);
    if (info == null) {
      _msg('Uploaded. Choose its unit to place it (Set unit, in the list below).');
      return;
    }
    ref.read(editorProvider.notifier).placeBackdrop(info);
    _msg(info.mpp != null ? 'Drawing placed at its exact scale (${drawingUnits[info.units] ?? info.units}). Move it into place if needed.' : 'Plan uploaded and placed. Calibrate its scale next.');
  }

  Future<void> _deleteUpload(BackdropInfo b) async {
    final st = ref.read(editorProvider);
    final branchId = st.branchId;
    if (branchId == null) return;
    final ok = await confirmDialog(context, title: 'Delete uploaded plan?', message: '${b.originalName ?? b.id} is removed from the server.', confirmLabel: 'Delete');
    if (!ok) return;
    try {
      await MapsService().deleteBackdrop(branchId, b.id);
      ref.invalidate(backdropsProvider(branchId));
      _msg('Deleted.');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _read({bool add = false}) async {
    final st = ref.read(editorProvider);
    final bd = st.level?.backdrop;
    final work = ref.read(editorProvider.notifier).convertBackdrop(addToProposal: add);
    // Round 17: the full-screen scan while the AI reads. It closes itself when the
    // reading works; when it fails it says why, calmly, with Try again and Close.
    final scan = mounted && bd != null && st.branchId != null ? showAiScan(context, done: work, branchId: st.branchId!, backdropKey: bd.id, crop: st.cropBox) : null;
    final err = await work;
    // The wallet changed (or the reason it failed may have): refresh the credit bar.
    ref.invalidate(aiStatusProvider);
    ref.invalidate(myCreditsProvider);
    if (err != null) {
      if (scan == null) {
        _msg(err, error: true);
      } else if (await scan && mounted) {
        await _read(add: add);
      }
      return;
    }
    if (!add) setState(() => _incOutline = null);
    final p = ref.read(editorProvider).proposal;
    final found = p?.scaleFound;
    if (found != null) {
      _msg('The plan\'s scale was found from the dimension ${found.mm} mm written on it. Undo puts the old scale back.');
    } else if (p != null) {
      _msg(add ? 'Added to the proposal. Review it before adding it to the floor.' : 'Read. Review the proposal before adding it to the floor.');
    }
  }

  Future<void> _accept(bool outlineDefault) async {
    final st = ref.read(editorProvider);
    final hasMatches = (st.proposal?.storeMatches.isNotEmpty ?? false) && _incSpaces;
    final err = await ref.read(editorProvider.notifier).acceptProposal(
          walls: _incWalls,
          openings: _incDoors,
          spaces: _incSpaces,
          outline: _incOutline ?? outlineDefault,
          linkStores: _linkStores && hasMatches,
        );
    if (err != null) {
      _msg(err, error: true);
    } else {
      _msg(_linkStores && hasMatches ? 'Added to the floor and the matched stores are linked. Undo removes the pieces in one step.' : 'Added to the floor. Undo reverts it in one step.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final level = st.level;
    final branchId = st.branchId;
    if (level == null || branchId == null) return const SizedBox.shrink();
    final ro = !st.editable;
    final bd = level.backdrop;
    final uploads = ref.watch(backdropsProvider(branchId));
    final info = bd == null ? null : uploads.valueOrNull?.cast<BackdropInfo?>().firstWhere((u) => u!.id == bd.id, orElse: () => null);
    final levelEmpty = level.walls.isEmpty && level.spaces.isEmpty && level.features.isEmpty;
    final busy = _busyLabel != null;

    Widget h(String t) => Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Text(t.toUpperCase(), style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1)));
    Widget gap() => const SizedBox(height: 6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        h('Plan on ${level.name}'),
        if (bd == null) ...[
          Text(
            'No plan placed on this level. Upload a picture (PNG, JPG, TIFF, WebP, BMP, GIF, HEIC), a PDF (you pick the page), or a drawing (SVG, DXF, DWG). DXF and DWG come in at their exact scale.',
            key: const ValueKey('plan-formats'),
            style: ts(11, color: p.muted),
          ),
          gap(),
          if (!ro) AppButton(label: _busyLabel ?? 'Upload plan', icon: Icons.upload_file, primary: true, onPressed: busy ? () {} : _upload),
        ] else ...[
          Text(info == null ? 'Plan ${bd.id.substring(0, 8)}…' : '${info.originalName ?? info.id.substring(0, 8)} · ${info.width}×${info.height} px', style: ts(11, color: p.muted)),
          Text('Scale: ${(1 / bd.mpp).toStringAsFixed(1)} px per metre · ${(info == null ? 0 : info.width * bd.mpp).toStringAsFixed(1)} m wide', style: ts(11, color: p.muted)),
          // A DXF or DWG at the scale its unit gives: no calibration needed.
          if (info?.mpp != null && (info!.mpp! - bd.mpp).abs() < 1e-7)
            Text('Scale from the drawing (${drawingUnits[info.units] ?? info.units}). Calibration is not needed.',
                key: const ValueKey('plan-exact-scale'), style: ts(11, w: FontWeight.w600, color: p.brand2)),
          gap(),
          // Not a Slider: its value bubble is an overlay portal, which cannot be laid
          // out inside this panel (see _OpacityBar).
          _OpacityBar(value: bd.opacity, enabled: !ro, onChanged: (v) => n.updateBackdrop((b) => b.opacity = v)),
          Row(
            children: [
              Expanded(child: Text('Locked (cannot be moved)', style: ts(11, color: p.ink))),
              Switch(value: bd.locked, onChanged: ro ? null : (v) => n.updateBackdrop((b) => b.locked = v), activeThumbColor: p.brand),
            ],
          ),
          if (!bd.locked && !ro) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AppButton(label: 'Rotate −15°', small: true, onPressed: () => n.updateBackdrop((b) => b.rot = ((b.rot - 15) % 360 + 360) % 360)),
                AppButton(label: 'Rotate +15°', small: true, onPressed: () => n.updateBackdrop((b) => b.rot = (b.rot + 15) % 360)),
                AppButton(label: '← 1 m', small: true, onPressed: () => n.updateBackdrop((b) => b.cx -= 1)),
                AppButton(label: '→ 1 m', small: true, onPressed: () => n.updateBackdrop((b) => b.cx += 1)),
                AppButton(label: '↑ 1 m', small: true, onPressed: () => n.updateBackdrop((b) => b.cz -= 1)),
                AppButton(label: '↓ 1 m', small: true, onPressed: () => n.updateBackdrop((b) => b.cz += 1)),
              ],
            ),
            gap(),
            Text('Centre ${bd.cx.toStringAsFixed(1)}, ${bd.cz.toStringAsFixed(1)} · rotation ${bd.rot.toStringAsFixed(0)}°', style: ts(10, color: p.sideNote)),
          ],
          h('Calibrate scale'),
          if (!st.calibrating) ...[
            Text('Click two points on the plan whose real distance you know (a dimension line, a door, a column spacing), then type the metres.', style: ts(11, color: p.muted)),
            gap(),
            if (!ro) AppButton(label: 'Start calibration', icon: Icons.straighten, onPressed: n.startCalibration),
          ] else ...[
            Text(st.calibPoints.length < 2 ? 'Click point ${st.calibPoints.length + 1} of 2 on the canvas.' : 'Real distance between the two points:', style: ts(11, color: p.ink)),
            gap(),
            if (st.calibPoints.length == 2)
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _metres,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: ts(12, color: p.ink),
                      decoration: InputDecoration(isDense: true, suffixText: 'm', contentPadding: const EdgeInsets.all(8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
                      onSubmitted: (_) => _applyCalibration(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: AppButton(label: 'Apply', primary: true, small: true, onPressed: _applyCalibration)),
                ],
              ),
            gap(),
            AppButton(label: 'Cancel', small: true, onPressed: n.cancelCalibration),
          ],
          h('Floor outline'),
          if (levelEmpty && !ro)
            AppButton(label: 'Make the floor the size of the plan', small: true, icon: Icons.fit_screen, onPressed: info == null ? () {} : () => n.fitOutlineToBackdrop(info.width, info.height))
          else
            Text(levelEmpty ? '' : 'Offered only while nothing is drawn on the level, so existing geometry never shifts under the picture.', style: ts(10, color: p.sideNote)),
          h('Read with AI'),
          Text(
            'The AI reads the floor outline, walls, doors and the rooms with their names and types. Anything it is unsure about is dashed in amber. You review it all before it touches the map. Each reading uses gateway credits.',
            style: ts(11, color: p.muted),
          ),
          gap(),
          _AiReadiness(onRetry: () => ref.invalidate(aiStatusProvider)),
          if (!ro) ...[
            gap(),
            _PartToRead(
              cropping: st.cropping,
              box: st.cropBox,
              onStart: n.startCrop,
              onCancel: n.cancelCrop,
              onClear: () => n.setCropBox(null),
            ),
            gap(),
            _ReadButtons(
              converting: st.converting,
              canAdd: st.proposal != null && st.proposal!.levelId == level.id,
              ready: ref.watch(aiStatusProvider).valueOrNull?.ready ?? false,
              onRead: () => _read(),
              onAdd: () => _read(add: true),
            ),
            if (st.lastCost != null) ...[
              gap(),
              Text(
                'Last reading: ${credits(st.lastCost!.credits)} credits${st.lastCost!.model == null ? '' : ' · ${st.lastCost!.model}'}',
                key: const ValueKey('ai-last-cost'),
                style: ts(10, color: p.sideNote),
              ),
            ],
          ],
          if (st.proposal != null && st.proposal!.levelId == level.id) ...[
            gap(),
            _ProposalReview(
              proposal: st.proposal!,
              incWalls: _incWalls,
              incDoors: _incDoors,
              incSpaces: _incSpaces,
              incOutline: _incOutline ?? level.outline == null,
              outlineReplaces: level.outline != null,
              linkStores: _linkStores,
              readOnly: ro,
              onToggle: ({walls, doors, spaces, outline, link}) => setState(() {
                _incWalls = walls ?? _incWalls;
                _incDoors = doors ?? _incDoors;
                _incSpaces = spaces ?? _incSpaces;
                _incOutline = outline ?? _incOutline;
                _linkStores = link ?? _linkStores;
              }),
              onAccept: () => _accept(level.outline == null),
              onDiscard: n.discardProposal,
            ),
          ],
          h('Remove'),
          if (!ro) AppButton(label: 'Remove plan from this level', small: true, icon: Icons.layers_clear, onPressed: n.removeBackdrop),
        ],
        h('Uploaded plans for this branch'),
        uploads.when(
          loading: () => const Shimmer(child: SkeletonLines(widths: [0.8, 0.55], height: 10)),
          error: (e, _) => Text(formatApiError(e), style: ts(11, color: p.warn)),
          data: (items) => items.isEmpty
              ? Text('Nothing uploaded yet.', style: ts(11, color: p.muted))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final u in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${u.originalName ?? u.id.substring(0, 8)} · ${u.isDrawing ? '${u.kind.toUpperCase()} drawing' : '${u.width}×${u.height}'}',
                                style: ts(11, color: p.ink),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!ro && (bd == null || bd.id != u.id)) Flexible(child: AppButton(label: u.needsUnit ? 'Set unit' : 'Place', small: true, onPressed: () => _placeSafely(u))),
                            if (!ro) IconButton(iconSize: 16, icon: const Icon(Icons.delete_outline), onPressed: () => _deleteUpload(u)),
                          ],
                        ),
                      ),
                    if (!ro) AppButton(label: _busyLabel ?? 'Upload another plan', small: true, icon: Icons.upload_file, onPressed: busy ? () {} : _upload),
                  ],
                ),
        ),
      ],
    );
  }

  void _applyCalibration() {
    final v = double.tryParse(_metres.text.trim());
    if (v == null || v <= 0) {
      _msg('Type the real distance in metres.', error: true);
      return;
    }
    final err = ref.read(editorProvider.notifier).applyCalibration(v);
    if (err != null) {
      _msg(err, error: true);
    } else {
      _metres.clear();
      _msg('Scale set.');
    }
  }
}

/// Whether AI reading can run, and the gateway wallet.
class _AiReadiness extends ConsumerWidget {
  const _AiReadiness({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    return ref.watch(aiStatusProvider).when(
          loading: () => const Shimmer(child: SkeletonLines(widths: [0.85, 0.5], height: 9)),
          error: (e, _) => Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(formatApiError(e), style: ts(11, color: p.warn)),
              AppButton(label: 'Try again', small: true, onPressed: onRetry),
            ],
          ),
          data: (s) {
            // Round 19: running out of credits shows the admin's own credits and Request credits instead.
            if (s.blocker != null && !s.outOfCredits) return Text(s.blocker!, key: const ValueKey('ai-blocker'), style: ts(11, color: p.warn));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AiReadingCredits(status: s),
                if (s.quotaError != null) Text(s.quotaError!, style: ts(11, color: p.warn)),
              ],
            );
          },
        );
  }
}

/// The whole plan, or a boxed part of it.
class _PartToRead extends StatelessWidget {
  const _PartToRead({required this.cropping, required this.box, required this.onStart, required this.onCancel, required this.onClear});

  final bool cropping;
  final List<double>? box;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final b = box;
    final String text;
    final List<Widget> actions;
    if (cropping) {
      text = 'Drag a box over the part of the plan to read.';
      actions = [AppButton(label: 'Cancel', small: true, onPressed: onCancel)];
    } else if (b != null) {
      final share = ((b[2] - b[0]) * (b[3] - b[1]) * 100).round().clamp(1, 100);
      text = 'Reading the boxed part ($share% of the plan).';
      actions = [
        AppButton(label: 'Box another part', small: true, icon: Icons.crop, onPressed: onStart),
        AppButton(label: 'Read the whole plan', small: true, onPressed: onClear),
      ];
    } else {
      text = 'Reading the whole plan. For a large plan, box one part at a time and add each to the proposal.';
      actions = [AppButton(label: 'Box a part', small: true, icon: Icons.crop, onPressed: onStart)];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, key: const ValueKey('ai-part'), style: ts(11, color: cropping ? p.brand2 : p.ink)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: actions),
      ],
    );
  }
}

class _ReadButtons extends StatelessWidget {
  const _ReadButtons({required this.converting, required this.canAdd, required this.ready, required this.onRead, required this.onAdd});

  final bool converting;
  final bool canAdd;
  final bool ready;
  final VoidCallback onRead;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (converting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(label: 'Reading…', icon: Icons.auto_awesome, primary: true, onPressed: () {}),
          const SizedBox(height: 4),
          Text('A large plan can take a few minutes.', style: ts(10, color: p.sideNote)),
        ],
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        AppButton(label: canAdd ? 'Read again (new proposal)' : 'Read with AI', icon: Icons.auto_awesome, primary: !canAdd, onPressed: ready ? onRead : () {}),
        if (canAdd) AppButton(label: 'Add to proposal', icon: Icons.add, primary: true, onPressed: ready ? onAdd : () {}),
      ],
    );
  }
}

class _ProposalReview extends StatelessWidget {
  const _ProposalReview({
    required this.proposal,
    required this.incWalls,
    required this.incDoors,
    required this.incSpaces,
    required this.incOutline,
    required this.outlineReplaces,
    required this.linkStores,
    required this.readOnly,
    required this.onToggle,
    required this.onAccept,
    required this.onDiscard,
  });

  final Proposal proposal;
  final bool incWalls;
  final bool incDoors;
  final bool incSpaces;
  final bool incOutline;
  final bool outlineReplaces;
  final bool linkStores;
  final bool readOnly;
  final void Function({bool? walls, bool? doors, bool? spaces, bool? outline, bool? link}) onToggle;
  final VoidCallback onAccept;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pr = proposal;
    final empty = pr.walls.isEmpty && pr.spaces.isEmpty && pr.outline == null;
    final named = pr.spaces.where((s) => s.name.isNotEmpty).length;
    final names = {for (final s in pr.spaces) s.id: s.name};
    Widget check(String label, bool value, void Function(bool v) on, {Key? key}) => CheckboxListTile(
          key: key,
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: value,
          title: Text(label, style: ts(11, color: p.ink)),
          onChanged: readOnly ? null : (v) => on(v ?? false),
        );
    // A Material, not a coloured box: the checkbox rows paint their ink on it.
    return Material(
      color: p.aiProposalPanel,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.aiProposal), borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(pr.sections > 1 ? 'AI proposal · ${pr.sections} parts' : 'AI proposal', style: ts(12, w: FontWeight.w800, color: p.aiProposal)),
            Text(
              '${pr.walls.length} walls · ${pr.openings.length} doors · ${pr.spaces.length} rooms ($named named)${pr.outline == null ? '' : ' · floor outline'}',
              style: ts(11, color: p.ink),
            ),
            if (pr.uncertain.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${pr.uncertain.length} unsure ${pr.uncertain.length == 1 ? 'piece is' : 'pieces are'} dashed in amber. Check them on the plan.', style: ts(11, color: p.aiUnsure)),
              ),
            for (final note in pr.notes) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note, style: ts(11, color: p.muted))),
            if (pr.cost != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('This proposal used ${credits(pr.cost!.credits)} credits.', style: ts(10, color: p.sideNote))),
            if (!readOnly) ...[
              const SizedBox(height: 6),
              Text('Click a piece on the canvas to drop it. Then add what is left:', style: ts(10, color: p.muted)),
              check('Walls', incWalls, (v) => onToggle(walls: v)),
              check('Doors (need walls)', incDoors, (v) => onToggle(doors: v)),
              check('Rooms', incSpaces, (v) => onToggle(spaces: v)),
              if (pr.outline != null) check(outlineReplaces ? 'Floor outline (replaces the current one)' : 'Floor outline', incOutline, (v) => onToggle(outline: v), key: const ValueKey('ai-outline')),
              if (pr.storeMatches.isNotEmpty) ...[
                check('Link matched stores (${pr.storeMatches.length})', linkStores && incSpaces, (v) => onToggle(link: v), key: const ValueKey('ai-link')),
                for (final m in pr.storeMatches)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Text('${names[m.spaceId]?.isNotEmpty == true ? names[m.spaceId] : 'Room'} → ${m.storeName}${m.exact ? '' : ' (close match)'}', style: ts(10.5, color: p.muted)),
                  ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: AppButton(label: 'Add to floor', primary: true, small: true, onPressed: empty ? () {} : onAccept)),
                  const SizedBox(width: 6),
                  Flexible(child: AppButton(label: 'Discard', small: true, onPressed: onDiscard)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks which unit a DXF or DWG drawing is in, when the file does not say
/// (owner decision 2026-10-22). Returns the unit key (mm, cm, m, in, ft).
class DrawingUnitPicker extends StatefulWidget {
  const DrawingUnitPicker({super.key, this.fileName});

  final String? fileName;

  @override
  State<DrawingUnitPicker> createState() => _DrawingUnitPickerState();
}

class _DrawingUnitPickerState extends State<DrawingUnitPicker> {
  String? _unit;
  String? _error;

  static final _spec = FieldSpec(
    name: 'unit',
    label: 'Drawing unit',
    kind: FieldKind.select,
    required: true,
    hint: 'Choose the unit…',
    options: [for (final e in drawingUnits.entries) SelectOption(e.key, '${e.value[0].toUpperCase()}${e.value.substring(1)} (${e.key})')],
    help: 'Most metric architectural drawings are in millimetres. A wrong unit makes the plan 10 or 1000 times too big or small.',
  );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AlertDialog(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('Which unit is this drawing in?', style: ts(16, w: FontWeight.w800, color: p.ink)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${widget.fileName ?? 'This drawing'} does not say its unit. Choose it, and the plan is placed at its exact scale.', style: ts(13, color: p.muted)),
              const SizedBox(height: 12),
              FieldBuilder(
                  spec: _spec,
                  value: _unit,
                  error: _error,
                  onChanged: (v) => setState(() {
                        _unit = v as String?;
                        _error = null;
                      })),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(label: 'Later', onPressed: () => Navigator.of(context).pop()),
        AppButton(
          label: 'Place at this scale',
          primary: true,
          onPressed: () {
            if (_unit == null) {
              setState(() => _error = 'Choose the unit.');
              return;
            }
            Navigator.of(context).pop(_unit);
          },
        ),
      ],
    );
  }
}

/// Picks the page of a multi-page PDF, with a preview of the page.
class PdfPagePicker extends StatefulWidget {
  const PdfPagePicker({super.key, required this.doc});

  final PdfDocument doc;

  @override
  State<PdfPagePicker> createState() => _PdfPagePickerState();
}

class _PdfPagePickerState extends State<PdfPagePicker> {
  int _page = 1;
  final Map<int, Future<Uint8List>> _previews = {};

  Future<Uint8List> _preview(int page) => _previews.putIfAbsent(page, () => widget.doc.render(page, maxSide: 900));

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final count = widget.doc.pageCount;
    return AlertDialog(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('Which page is the floor plan?', style: ts(16, w: FontWeight.w800, color: p.ink)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('This PDF has $count pages. The chosen page is turned into a picture and uploaded.', style: ts(13, color: p.muted)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 1; i <= count; i++)
                    ChoiceChip(
                      key: ValueKey('pdf-page-$i'),
                      label: Text('$i', style: ts(12, w: FontWeight.w700, color: i == _page ? p.brand2 : p.ink)),
                      selected: i == _page,
                      showCheckmark: false,
                      selectedColor: p.soft,
                      backgroundColor: p.panel,
                      side: BorderSide(color: i == _page ? p.brand : p.line),
                      onSelected: (_) => setState(() => _page = i),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 4 / 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(border: Border.all(color: p.line), borderRadius: BorderRadius.circular(8)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: FutureBuilder<Uint8List>(
                      key: ValueKey(_page),
                      future: _preview(_page),
                      builder: (context, snap) {
                        if (snap.hasError) return Center(child: Text('No preview for this page.', style: ts(12, color: p.muted)));
                        if (!snap.hasData) return const Shimmer(child: SkeletonBox(height: double.infinity, radius: 0));
                        return Image.memory(snap.data!, fit: BoxFit.contain, gaplessPlayback: true);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        AppButton(label: 'Use page $_page', primary: true, onPressed: () => Navigator.of(context).pop(_page)),
      ],
    );
  }
}

/// Opacity control without any overlay. Tap or drag along the bar.
class _OpacityBar extends StatelessWidget {
  const _OpacityBar({required this.value, required this.enabled, required this.onChanged});

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  void _set(BuildContext context, Offset local) {
    final box = context.findRenderObject() as RenderBox;
    final f = (local.dx / box.size.width).clamp(0.0, 1.0);
    final v = 0.05 + f * 0.95;
    onChanged(((v * 100).round() / 100).clamp(0.05, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final f = ((value - 0.05) / 0.95).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text('Opacity', style: ts(11, color: p.ink)),
          const SizedBox(width: 8),
          Expanded(
            child: Builder(
              builder: (ctx) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: enabled ? (d) => _set(ctx, d.localPosition) : null,
                onHorizontalDragUpdate: enabled ? (d) => _set(ctx, d.localPosition) : null,
                child: SizedBox(
                  height: 22,
                  child: CustomPaint(
                    painter: _BarPainter(fraction: f, track: p.fieldLine, fill: enabled ? p.brand : p.hint),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 34, child: Text('${(value * 100).round()}%', style: ts(11, color: p.muted), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({required this.fraction, required this.track, required this.fill});

  final double fraction;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = track
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(
        Offset(0, y),
        Offset(size.width * fraction, y),
        Paint()
          ..color = fill
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(Offset(size.width * fraction, y), 7, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.fraction != fraction || old.fill != fill;
}
