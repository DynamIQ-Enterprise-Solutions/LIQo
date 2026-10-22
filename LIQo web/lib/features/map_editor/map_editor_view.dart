import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import 'blueprint_panel.dart';
import 'editor_state.dart';
import 'guided/guided_editor.dart';
import 'map3d_panel.dart';
import 'map_canvas.dart';
import 'maps_service.dart';
import 'plan_upload.dart';
import 'properties_panel.dart';

/// Mall admin map editor: branch picker, tool rail, 2D canvas with the 3D
/// preview beside it (Round 17), right-hand panel.
class MapEditorView extends ConsumerStatefulWidget {
  const MapEditorView({super.key});

  @override
  ConsumerState<MapEditorView> createState() => _MapEditorViewState();
}

class _MapEditorViewState extends ConsumerState<MapEditorView> {
  int _tab = 0;

  /// The easy editor or the full tools, remembered on this device (Round 18).
  static const _modeKey = 'map.editor.guided';

  @override
  void initState() {
    super.initState();
    final guided = ref.read(sharedPrefsProvider).getBool(_modeKey) ?? true;
    if (ref.read(editorProvider).guided != guided) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(editorProvider.notifier).setGuided(guided);
      });
    }
  }

  void _setGuided(bool on) {
    ref.read(editorProvider.notifier).setGuided(on);
    ref.read(sharedPrefsProvider).setBool(_modeKey, on);
  }

  String? _startBusy;

  /// Starts the branch's map from a plan (Round 17): upload (or reuse an upload),
  /// ask a drawing's unit if needed, create the map without a made-up outline,
  /// place the plan, give the floor the drawing's exact size, open Blueprint.
  Future<void> _startFromPlan([BackdropInfo? existing]) async {
    final st = ref.read(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final branchId = st.branchId;
    if (branchId == null) return;
    final up = PlanUpload(context, ref, onBusy: (label) {
      if (mounted) setState(() => _startBusy = label);
    });
    try {
      final uploaded = existing ?? await up.pickAndUpload(branchId);
      if (uploaded == null) return;
      final info = await up.resolveUnit(branchId, uploaded);
      if (info == null) {
        _msg('The drawing is uploaded. Choose its unit to start the map ("Start with this plan").');
        return;
      }
      if (mounted) setState(() => _startBusy = 'Starting the map…');
      final err = await n.createMap(outline: false);
      if (err != null) throw ShownError(err);
      n.placeBackdrop(info);
      if (info.mpp != null) n.fitOutlineToBackdrop(info.width, info.height);
      await n.save();
      n.requestFit();
      if (mounted) setState(() => _tab = 3);
      // Easy editor: on to the scale (pictures) or straight to reading (exact drawings).
      n.setGuidedStep(info.mpp != null ? 2 : 1);
      _msg(info.mpp != null
          ? 'Map started at the drawing\'s exact size (${drawingUnits[info.units] ?? info.units}). Read it with AI next, or trace it.'
          : 'Map started on your plan. Calibrate its scale next, then read it with AI or trace it.');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    } finally {
      if (mounted) setState(() => _startBusy = null);
    }
  }

  static final _fmt = DateFormat('MMM d, h:mm a');

  void _msg(String text, {bool error = false}) {
    final m = ref.read(messagesProvider.notifier);
    error ? m.showError(text) : m.showSuccess(text);
  }

  Future<void> _createMap() async {
    final n = ref.read(editorProvider.notifier);
    await showAppForm(
      context: context,
      title: 'Start a map for this branch',
      subtitle: 'One rectangular ground floor to begin with. You can reshape the outline and add buildings and levels afterwards.',
      submitLabel: 'Create map',
      initial: const {'buildingName': 'Main building', 'levelName': 'Ground floor', 'width': 120, 'depth': 80},
      fields: const [
        FieldSpec(name: 'buildingName', label: 'Building name', required: true, maxLength: 80),
        FieldSpec(name: 'levelName', label: 'First level name', required: true, maxLength: 60),
        FieldSpec(name: 'width', label: 'Width (m)', kind: FieldKind.decimal, required: true, min: 5, max: 2000),
        FieldSpec(name: 'depth', label: 'Depth (m)', kind: FieldKind.decimal, required: true, min: 5, max: 2000),
      ],
      onSubmit: (v) async {
        final err = await n.createMap(
          buildingName: v['buildingName'] as String,
          levelName: v['levelName'] as String,
          width: (v['width'] as num).toDouble(),
          depth: (v['depth'] as num).toDouble(),
        );
        if (err != null) throw ShownError(err);
      },
    );
  }

  Future<void> _publish() async {
    final st = ref.read(editorProvider);
    if (st.publishProblems.isNotEmpty) {
      setState(() => _tab = 1);
      _msg('Fix the issues listed under Issues before publishing.', error: true);
      return;
    }
    final ok = await showAppForm(
      context: context,
      title: 'Publish this map?',
      subtitle: 'The published version becomes the live map for this branch. Previous versions stay available for rollback.',
      submitLabel: 'Publish',
      fields: const [FieldSpec(name: 'note', label: 'Note (optional)', maxLength: 200, hint: 'What changed')],
      onSubmit: (v) async {
        final err = await ref.read(editorProvider.notifier).publish(note: v['note'] as String?);
        if (err != null) throw ShownError(err);
      },
    );
    if (ok) _msg('Map published.');
  }

  Future<void> _history() async {
    final st = ref.read(editorProvider);
    final p = context.pal;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Published versions', style: ts(16, w: FontWeight.w800, color: p.ink)),
        content: SizedBox(
          width: 460,
          child: st.versions.isEmpty
              ? Text('Nothing published yet.', style: ts(12, color: p.muted))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final v in st.versions)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Version ${v.version}${v.version == st.publishedVersion ? ' · live' : ''}', style: ts(13, w: FontWeight.w700, color: p.ink)),
                        subtitle: Text('${_fmt.format(v.publishedAt)} · ${v.publishedByName ?? ''} · ${v.spaceCount} spaces${v.note == null || v.note!.isEmpty ? '' : ' · ${v.note}'}',
                            style: ts(11, color: p.muted)),
                        trailing: st.editable && v.version != st.publishedVersion
                            ? AppButton(
                                label: 'Roll back',
                                small: true,
                                onPressed: () async {
                                  Navigator.of(ctx).pop();
                                  final ok = await confirmDialog(context,
                                      title: 'Roll back to version ${v.version}?',
                                      message: 'A new version is published with that layout, and it becomes the current draft.',
                                      confirmLabel: 'Roll back');
                                  if (!ok) return;
                                  final err = await ref.read(editorProvider.notifier).rollback(v.version);
                                  err == null ? _msg('Rolled back to version ${v.version}.') : _msg(err, error: true);
                                },
                              )
                            : null,
                      ),
                  ],
                ),
        ),
        actions: [AppButton(label: 'Close', onPressed: () => Navigator.of(ctx).pop())],
      ),
    );
  }

  Future<void> _copyTo() async {
    final n = ref.read(editorProvider.notifier);
    await showAppForm(
      context: context,
      title: 'Copy this map to another branch',
      subtitle: 'The copy gets new ids. Store links are not copied; link stores in the other branch afterwards.',
      submitLabel: 'Copy',
      fields: const [
        FieldSpec(name: 'target', label: 'Target branch', kind: FieldKind.lookup, lookup: 'branches', required: true, hint: 'Choose a branch…'),
        FieldSpec(name: 'overwrite', label: 'Replace the target draft if it already has a map', kind: FieldKind.toggle),
      ],
      onSubmit: (v) async {
        final target = (v['target'] as List<LookupItem>).first.id;
        final err = await n.copyTo(target, overwrite: v['overwrite'] == true);
        if (err != null) throw ShownError(err);
        _msg('Map copied.');
        ref.invalidate(mapListProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final list = ref.watch(mapListProvider);
    final height = (MediaQuery.sizeOf(context).height - 66 - 70).clamp(520.0, 2000.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'Mall admin / Map editor',
          title: 'Map editor',
          subtitle: 'Draw the branch map in 2D. Drafts save automatically; publishing makes a version live.',
          actions: [
            if (st.doc != null && st.canEdit) AppButton(label: 'History', icon: Icons.history, onPressed: _history),
            if (st.doc != null && st.canEdit) AppButton(label: 'Copy to…', icon: Icons.copy_outlined, onPressed: _copyTo),
            if (st.doc != null && st.editable) AppButton(label: 'Publish', icon: Icons.publish_outlined, primary: true, onPressed: _publish),
          ],
        ),
        // Branch picker + status strip
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Branch:', style: ts(12, color: p.muted)),
              list.when(
                loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => Text(formatApiError(e), style: ts(12, color: p.warn)),
                data: (items) => AppDropdown<int>(
                  // The selected value must be one of the items or the dropdown asserts.
                  value: items.any((m) => m.branchId == st.branchId) ? st.branchId! : (items.isEmpty ? 0 : items.first.branchId),
                  items: [
                    if (items.isEmpty) const DropdownMenuItem(value: 0, child: Text('No branches in your scope')),
                    for (final m in items)
                      DropdownMenuItem(
                        value: m.branchId,
                        child: Text('${m.mallName} · ${m.branchName}${m.hasMap ? '' : ' (no map)'}${m.publishedVersion != null ? ' · v${m.publishedVersion}' : ''}'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null && v != 0) n.open(v);
                  },
                ),
              ),
              if (st.branchId == null && list.valueOrNull?.isNotEmpty == true) AppButton(label: 'Open', small: true, primary: true, onPressed: () => n.open(list.valueOrNull!.first.branchId)),
              if (st.doc != null) ...[
                _SaveChip(st: st),
                _LockChip(
                    st: st,
                    onRetry: () async {
                      final err = await n.acquireLock();
                      if (err != null) _msg(err, error: true);
                    }),
                Text('Draft v${st.draftVersion}${st.publishedVersion != null ? ' · published v${st.publishedVersion}' : ' · not published'}', style: ts(11, color: p.muted)),
                AppButton(label: '', small: true, icon: Icons.undo, onPressed: st.undoDepth > 0 ? n.undo : () {}),
                AppButton(label: '', small: true, icon: Icons.redo, onPressed: st.redoDepth > 0 ? n.redo : () {}),
                AppButton(label: st.snap ? 'Snap on' : 'Snap off', small: true, icon: st.snap ? Icons.grid_on : Icons.grid_off, onPressed: n.toggleSnap),
                AppButton(label: 'Reload', small: true, icon: Icons.refresh, onPressed: n.reload),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (st.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Notice(bold: st.saveState == SaveState.conflict ? 'Conflict.' : 'Note.', text: st.error!),
          ),
        if (st.loading)
          const Shimmer(child: SkeletonCard(child: SkeletonChart(height: 360)))
        else if (st.branchId == null)
          AppCard(padding: const EdgeInsets.all(28), child: Text('Choose a branch to open its map.', style: ts(13, color: p.muted)))
        else if (st.doc == null)
          _StartMap(st: st, busy: _startBusy, onUpload: () => _startFromPlan(), onUseUpload: _startFromPlan, onManual: _createMap)
        else ...[
          if (st.guided) ...[
            GuidedStepBar(onAdvanced: () => _setGuided(false)),
            const SizedBox(height: 10),
          ] else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('guided-back-to-easy'),
                onPressed: () => _setGuided(true),
                icon: Icon(Icons.auto_fix_high, size: 16, color: p.brand2),
                label: Text('Back to the easy editor', style: ts(12, w: FontWeight.w700, color: p.brand2)),
              ),
            ),
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fixed width: a Row gives unbounded width otherwise, and the
                // Tooltip overlays inside the rail cannot be laid out unconstrained.
                // The easy editor has no icon rail: its tools are in words in the panel.
                if (!st.guided) ...[
                  SizedBox(width: 54, child: _ToolRail(st: st, n: n)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LevelTabs(st: st, n: n),
                      const SizedBox(height: 8),
                      // The 2D canvas with the 3D preview beside it (Round 17, US-036).
                      const Expanded(child: _CanvasWith3d()),
                      const SizedBox(height: 6),
                      Text(
                        st.guided
                            ? 'Drag to move around · wheel or + / − to zoom · click a room or wall to select it · Esc cancels'
                            : 'Left click: use tool · Right/middle drag: pan · Wheel: zoom · V select · W wall · S space · O opening · F feature · C connector · Enter/double-click: finish shape · Esc: cancel · Del: delete · Ctrl+Z/Y: undo/redo · Shift: free angle',
                        style: ts(10, color: p.sideNote),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 310,
                  child: st.guided
                      ? AppCard(child: GuidedPanel(onPublish: _publish))
                      : AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  for (final (i, label) in ['Properties', 'Issues', 'Structure', 'Blueprint'].indexed)
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _tab = i),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == i ? p.brand : p.softLine, width: _tab == i ? 2 : 1))),
                                          child: Center(
                                            child: Text(
                                              i == 1 && (st.publishProblems.isNotEmpty || st.warnings.isNotEmpty) ? '$label (${st.publishProblems.length + st.warnings.length})' : label,
                                              style: ts(11, w: FontWeight.w700, color: _tab == i ? p.brand2 : p.slate),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(12),
                                  child: switch (_tab) {
                                    1 => _IssuesPanel(st: st, n: n),
                                    2 => _StructurePanel(st: st, n: n),
                                    3 => const BlueprintPanel(),
                                    _ => const PropertiesPanel(),
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SaveChip extends StatelessWidget {
  const _SaveChip({required this.st});

  final EditorData st;

  @override
  Widget build(BuildContext context) {
    final (label, kind, icon) = switch (st.saveState) {
      SaveState.dirty => ('Unsaved changes', PillKind.pending, Icons.edit_outlined),
      SaveState.saving => ('Saving…', PillKind.blue, Icons.sync),
      SaveState.saved => ('Saved', PillKind.green, Icons.check_circle_outline),
      SaveState.error => ('Save failed', PillKind.off, Icons.error_outline),
      SaveState.conflict => ('Conflict · reload', PillKind.off, Icons.warning_amber),
      SaveState.none => ('No changes', PillKind.off, Icons.circle_outlined),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: context.pal.muted), const SizedBox(width: 4), Pill(label, kind: kind)]);
  }
}

class _LockChip extends StatelessWidget {
  const _LockChip({required this.st, required this.onRetry});

  final EditorData st;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!st.canEdit) return const Pill('Read-only', kind: PillKind.off);
    final lock = st.lock;
    if (lock?.mine ?? false) return const Pill('You are editing', kind: PillKind.green);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Pill(lock == null ? 'Not locked' : 'Locked by ${lock.userName ?? 'someone'}', kind: PillKind.pending),
        const SizedBox(width: 6),
        AppButton(label: 'Take lock', small: true, onPressed: onRetry),
      ],
    );
  }
}

class _ToolRail extends StatelessWidget {
  const _ToolRail({required this.st, required this.n});

  final EditorData st;
  final EditorNotifier n;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cat = st.catalog;
    final enabled = st.editable;

    // No Tooltip here: its overlay portal cannot be laid out inside this rail
    // (Flutter asserts in _RenderTheater.performLayout and the page freezes).
    // The label under each icon says what the tool is; shortcuts are in the help line.
    Widget tool(EditorTool t, IconData icon, String label) {
      final active = st.tool == t;
      final color = !enabled
          ? p.hint
          : active
              ? p.brand2
              : p.slate;
      return Material(
        color: active ? p.soft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? () => n.setTool(t) : null,
          child: SizedBox(
            width: 42,
            height: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 2),
                Text(label, style: ts(8, w: FontWeight.w700, color: color), overflow: TextOverflow.clip, maxLines: 1),
              ],
            ),
          ),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Column(
        children: [
          tool(EditorTool.select, Icons.near_me_outlined, 'Select'),
          tool(EditorTool.wall, Icons.horizontal_rule, 'Wall'),
          tool(EditorTool.space, Icons.crop_din, 'Space'),
          tool(EditorTool.outline, Icons.polyline, 'Outline'),
          tool(EditorTool.hole, Icons.filter_center_focus, 'Hole'),
          tool(EditorTool.opening, Icons.sensor_door_outlined, 'Opening'),
          Divider(color: p.line, height: 14),
          // Plain buttons + showMenu(): PopupMenuButton wraps itself in a Tooltip
          // (an overlay portal), which asserts inside this rail and freezes the page.
          _RailMenuButton(
            icon: Icons.place_outlined,
            label: 'Feature',
            active: st.tool == EditorTool.feature,
            enabled: enabled && cat != null,
            items: [
              for (final c in cat?.categories ?? const <String>[]) ...[
                PopupMenuItem<String>(enabled: false, height: 28, child: Text(c.toUpperCase(), style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1))),
                for (final f in (cat?.features.values ?? const <FeatureDef>[]).where((f) => f.category == c))
                  PopupMenuItem<String>(value: f.key, height: 32, child: Text(f.label, style: ts(12, color: p.ink))),
              ],
            ],
            onSelected: n.setFeatureType,
          ),
          _RailMenuButton(
            icon: Icons.stairs_outlined,
            label: 'Connect',
            active: st.tool == EditorTool.connector,
            enabled: enabled && cat != null,
            items: [for (final k in cat?.connectorKinds ?? const <String>[]) PopupMenuItem<String>(value: k, height: 32, child: Text(k.replaceAll('_', ' '), style: ts(12, color: p.ink)))],
            onSelected: n.setConnectorKind,
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.delete_outline, size: 19), color: p.slate, onPressed: enabled && !st.selection.isEmpty ? n.deleteSelection : null),
        ],
      ),
    );
  }
}

/// Rail button that opens a menu with showMenu() (Navigator route, no overlay portal).
class _RailMenuButton extends StatelessWidget {
  const _RailMenuButton({required this.icon, required this.label, required this.active, required this.enabled, required this.items, required this.onSelected});

  final IconData icon;
  final String label;
  final bool active;
  final bool enabled;
  final List<PopupMenuEntry<String>> items;
  final ValueChanged<String> onSelected;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(topLeft.dx + box.size.width + 4, topLeft.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final value = await showMenu<String>(context: context, position: position, items: items);
    if (value != null) onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = !enabled
        ? p.hint
        : active
            ? p.brand2
            : p.slate;
    return Material(
      color: active ? p.soft : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? () => _open(context) : null,
        child: SizedBox(
          width: 42,
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 2),
              Text(label, style: ts(8, w: FontWeight.w700, color: color), maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelTabs extends StatelessWidget {
  const _LevelTabs({required this.st, required this.n});

  final EditorData st;
  final EditorNotifier n;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final doc = st.doc!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final b in doc.buildings) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(b.name, style: ts(11, w: FontWeight.w800, color: p.sideNote)),
            ),
            for (final l in b.levels)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Material(
                  color: st.levelId == l.id ? p.soft : p.panel,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: st.levelId == l.id ? p.brand : p.line)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => n.selectLevel(l.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text('${l.name} · ${l.elevation.toStringAsFixed(0)} m', style: ts(12, w: FontWeight.w700, color: st.levelId == l.id ? p.brand2 : p.slate)),
                    ),
                  ),
                ),
              ),
            if (st.editable)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: AppButton(label: '', small: true, icon: Icons.add, onPressed: () => n.addLevel(b.id)),
              ),
          ],
          if (st.editable) AppButton(label: 'Add building', small: true, icon: Icons.domain_add, onPressed: n.addBuilding),
        ],
      ),
    );
  }
}

class _IssuesPanel extends StatelessWidget {
  const _IssuesPanel({required this.st, required this.n});

  final EditorData st;
  final EditorNotifier n;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (st.publishProblems.isEmpty && st.warnings.isEmpty) {
      return Text('No issues. The map can be published.', style: ts(12, color: p.green));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (st.publishProblems.isNotEmpty) ...[
          Text('BLOCKS PUBLISHING', style: ts(10, w: FontWeight.w800, color: p.warn, ls: 1)),
          const SizedBox(height: 6),
          for (final s in st.publishProblems)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 14, color: p.warn),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s, style: ts(11, color: p.ink))),
                ],
              ),
            ),
          const SizedBox(height: 10),
        ],
        if (st.warnings.isNotEmpty) ...[
          Text('WARNINGS', style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1)),
          const SizedBox(height: 6),
          for (final w in st.warnings)
            InkWell(
              onTap: w.ids.isEmpty ? null : () => n.selectById(w.ids.first),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, size: 14, color: p.warn),
                    const SizedBox(width: 6),
                    Expanded(child: Text(w.message, style: ts(11, color: p.ink))),
                  ],
                ),
              ),
            ),
          Text('Warnings never block publishing. Click one to select the element.', style: ts(10, color: p.sideNote)),
        ],
      ],
    );
  }
}

class _StructurePanel extends ConsumerWidget {
  const _StructurePanel({required this.st, required this.n});

  final EditorData st;
  final EditorNotifier n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final doc = st.doc!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in doc.buildings) ...[
          Row(
            children: [
              Expanded(child: Text(b.name, style: ts(12, w: FontWeight.w800, color: p.ink))),
              if (st.editable && doc.buildings.length > 1)
                IconButton(
                  iconSize: 16,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirmDialog(context, title: 'Delete building?', message: '${b.name} and all its levels will be removed.', confirmLabel: 'Delete')) n.deleteBuilding(b.id);
                  },
                ),
            ],
          ),
          for (final l in b.levels)
            // A ListTile paints its highlight on the nearest Material; the card's
            // own background would hide it, so each tile gets its own.
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                selected: st.levelId == l.id,
                selectedTileColor: p.soft,
                title: Text(l.name, style: ts(12, color: p.ink)),
                subtitle: Text('${l.elevation.toStringAsFixed(1)} m · ${l.spaces.length} spaces · ${l.walls.length} walls · ${l.features.length} features', style: ts(10, color: p.muted)),
                onTap: () => n.selectLevel(l.id),
                trailing: st.editable && doc.allLevels.length > 1
                    ? IconButton(
                        iconSize: 16,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmDialog(context, title: 'Delete level?', message: '${l.name} will be removed. Connectors that lose an endpoint are updated.', confirmLabel: 'Delete')) {
                            n.deleteLevel(l.id);
                          }
                        },
                      )
                    : null,
              ),
            ),
          if (st.editable) Align(alignment: Alignment.centerLeft, child: LinkButton('+ Add level to ${b.name}', onPressed: () => n.addLevel(b.id))),
          const SizedBox(height: 10),
        ],
        if (st.editable) AppButton(label: 'Add building', small: true, icon: Icons.domain_add, onPressed: n.addBuilding),
        const SizedBox(height: 14),
        Text('CONNECTORS (${doc.connectors.length})', style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1)),
        const SizedBox(height: 6),
        if (doc.connectors.isEmpty) Text('None yet. Use the Connector tool to place stairs, escalators, elevators, ramps, bridges and walkways.', style: ts(11, color: p.muted)),
        for (final c in doc.connectors)
          Material(
            color: Colors.transparent,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${c.name.isNotEmpty ? c.name : c.kind} · ${c.endpoints.length} endpoints${c.oneWay ? ' · one-way' : ''}', style: ts(12, color: p.ink)),
              subtitle: Text(c.endpoints.map((e) => doc.level(e.level)?.name ?? '?').join(' ↔ '), style: ts(10, color: p.muted)),
              onTap: () => n.selectById(c.id),
            ),
          ),
        const SizedBox(height: 14),
        Text('Document: ${doc.buildings.length} buildings, ${doc.allLevels.length} levels, ${doc.spaceCount} spaces.', style: ts(10, color: p.sideNote)),
      ],
    );
  }
}

/// "No map yet" (Round 17, owner decision): uploading the floor plan is the way
/// to start; an empty map drawn by hand is the quiet fallback. Plans uploaded
/// earlier (e.g. a drawing whose unit was left for later) can start the map too.
class _StartMap extends ConsumerWidget {
  const _StartMap({required this.st, required this.busy, required this.onUpload, required this.onUseUpload, required this.onManual});

  final EditorData st;
  final String? busy;
  final VoidCallback onUpload;
  final void Function(BackdropInfo info) onUseUpload;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final uploads = st.branchId == null || !st.canEdit ? null : ref.watch(backdropsProvider(st.branchId!));
    return AppCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${st.branchName} has no map yet.', style: ts(15, w: FontWeight.w800, color: p.ink)),
          const SizedBox(height: 6),
          if (!st.canEdit)
            Text('A mall admin of this branch starts its map.', style: ts(12, color: p.muted))
          else ...[
            Text('Start with your floor plan', key: const ValueKey('start-map-title'), style: ts(13, w: FontWeight.w700, color: p.brand2)),
            const SizedBox(height: 4),
            Text(
              'Upload a picture (PNG, JPG, TIFF, WebP, BMP, GIF, HEIC), a PDF, or a drawing (SVG, DXF, DWG). The map starts on it: a DXF or DWG at its exact size, a picture after you calibrate it. Then read it with AI, or trace it.',
              style: ts(12, color: p.muted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppButton(label: busy ?? 'Upload a floor plan', icon: Icons.upload_file, primary: true, onPressed: busy == null ? onUpload : () {}),
              ],
            ),
            if (uploads?.valueOrNull?.isNotEmpty == true) ...[
              const SizedBox(height: 18),
              Text('OR START WITH A PLAN ALREADY UPLOADED', style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1)),
              const SizedBox(height: 8),
              for (final u in uploads!.value!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text('${u.originalName ?? u.id.substring(0, 8)} · ${u.isDrawing ? '${u.kind.toUpperCase()} drawing' : '${u.width}×${u.height}'}',
                              style: ts(12, color: p.ink), overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Flexible(child: AppButton(label: 'Start with this plan', small: true, onPressed: busy == null ? () => onUseUpload(u) : () {})),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 18),
            InkWell(
              key: const ValueKey('start-map-manual'),
              onTap: busy == null ? onManual : null,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'No plan? ', style: ts(12, color: p.muted)),
                    TextSpan(text: 'Create an empty map by hand', style: ts(12, w: FontWeight.w700, color: p.brand2).copyWith(decoration: TextDecoration.underline, decorationColor: p.brand2)),
                  ]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The 2D canvas with the 3D preview beside it (Round 17, US-036). The divider
/// between them can be dragged; the 3D side collapses to a slim strip, and that
/// choice is remembered on this device.
class _CanvasWith3d extends ConsumerStatefulWidget {
  const _CanvasWith3d();

  @override
  ConsumerState<_CanvasWith3d> createState() => _CanvasWith3dState();
}

class _CanvasWith3dState extends ConsumerState<_CanvasWith3d> {
  static const _prefKey = 'map3d.collapsed';
  double _share = 0.4;
  bool? _collapsed;

  void _setCollapsed(bool v) {
    setState(() => _collapsed = v);
    ref.read(sharedPrefsProvider).setBool(_prefKey, v);
  }

  @override
  Widget build(BuildContext context) {
    const canvas = AppCard(child: ClipRRect(borderRadius: BorderRadius.all(Radius.circular(14)), child: MapCanvas()));
    return LayoutBuilder(
      builder: (context, c) {
        final stored = ref.read(sharedPrefsProvider).getBool(_prefKey);
        // Open by default whenever the canvas keeps a usable width beside it.
        final tooNarrow = c.maxWidth < 480;
        final collapsed = tooNarrow || (_collapsed ?? stored ?? c.maxWidth < 600);
        if (collapsed) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: canvas),
              const SizedBox(width: 8),
              SizedBox(width: 34, child: Map3dCollapsed(key: const ValueKey('map3d-expand'), onExpand: tooNarrow ? () {} : () => _setCollapsed(false))),
            ],
          );
        }
        final upper = math.max(220.0, c.maxWidth - 280);
        final w3 = (c.maxWidth * _share).clamp(220.0, upper);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(child: canvas),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                key: const ValueKey('map3d-divider'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => setState(() => _share = ((w3 - d.delta.dx) / c.maxWidth).clamp(0.25, 0.65)),
                child: SizedBox(
                  width: 12,
                  child: Center(child: Container(width: 3, height: 36, decoration: BoxDecoration(color: context.pal.fieldLine, borderRadius: BorderRadius.circular(2)))),
                ),
              ),
            ),
            SizedBox(width: w3, child: Map3dPanel(key: const ValueKey('map3d-panel'), onCollapse: () => _setCollapsed(true))),
          ],
        );
      },
    );
  }
}
