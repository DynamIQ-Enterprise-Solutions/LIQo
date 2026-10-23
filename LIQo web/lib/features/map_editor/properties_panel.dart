import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/widgets/common.dart';
import 'editor_state.dart';
import 'map_models.dart';

/// Edits the selected element by number and name. Every change goes through the
/// editor notifier so it is undoable and autosaved.
class PropertiesPanel extends ConsumerWidget {
  const PropertiesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final p = context.pal;
    final level = st.level;
    final doc = st.doc;
    final sel = st.selection;
    if (doc == null || level == null) return const SizedBox.shrink();
    final ro = !st.editable;

    Widget section(String title, List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title.toUpperCase(), style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1)),
            const SizedBox(height: 8),
            ...children,
          ],
        );

    Widget gap() => const SizedBox(height: 6);

    switch (sel.kind) {
      case SelKind.wall:
        final w = level.wallById(sel.id);
        if (w == null) return const SizedBox.shrink();
        return section('Wall', [
          _Num(label: 'Thickness (m)', value: w.t, min: 0.05, max: 2, readOnly: ro, onChanged: (v) => n.edit((_, __) => w.t = v)),
          _Select(label: 'Kind', value: w.kind, options: st.catalog?.wallKinds ?? const ['solid'], readOnly: ro, onChanged: (v) => n.edit((_, __) => w.kind = v)),
          _Num(label: 'Start x', value: w.a[0], readOnly: ro, onChanged: (v) => n.edit((_, __) => w.a = [v, w.a[1]])),
          _Num(label: 'Start z', value: w.a[1], readOnly: ro, onChanged: (v) => n.edit((_, __) => w.a = [w.a[0], v])),
          _Num(label: 'End x', value: w.b[0], readOnly: ro, onChanged: (v) => n.edit((_, __) => w.b = [v, w.b[1]])),
          _Num(label: 'End z', value: w.b[1], readOnly: ro, onChanged: (v) => n.edit((_, __) => w.b = [w.b[0], v])),
          Text('Length ${w.length.toStringAsFixed(2)} m', style: ts(11, color: p.muted)),
          gap(),
          if (!ro) AppButton(label: 'Split in the middle', small: true, icon: Icons.content_cut, onPressed: () => n.splitWall(w.id, 0.5)),
          gap(),
          if (!ro) AppButton(label: 'Delete wall', small: true, icon: Icons.delete_outline, onPressed: n.deleteSelection),
        ]);

      case SelKind.opening:
        final o = level.openings.cast<Opening?>().firstWhere((x) => x!.id == sel.id, orElse: () => null);
        if (o == null) return const SizedBox.shrink();
        return section('Opening', [
          _Select(label: 'Kind', value: o.kind, options: st.catalog?.openingKinds ?? const ['door'], readOnly: ro, onChanged: (v) => n.edit((_, __) => o.kind = v)),
          _Text(label: 'Label', value: o.label, readOnly: ro, onChanged: (v) => n.edit((_, __) => o.label = v)),
          _Num(label: 'Width (m)', value: o.w, min: 0.4, max: 30, readOnly: ro, onChanged: (v) => n.edit((_, __) => o.w = v)),
          _Num(label: 'Position along wall (0–1)', value: o.at, min: 0, max: 1, step: 0.01, readOnly: ro, onChanged: (v) => n.edit((_, __) => o.at = v.clamp(0, 1))),
          Text('On wall ${o.wall}', style: ts(11, color: p.muted)),
          gap(),
          if (!ro) AppButton(label: 'Delete opening', small: true, icon: Icons.delete_outline, onPressed: n.deleteSelection),
        ]);

      case SelKind.space:
        final s = level.spaces.cast<Space?>().firstWhere((x) => x!.id == sel.id, orElse: () => null);
        if (s == null) return const SizedBox.shrink();
        final links = st.storeLinks.where((l) => l.spaceKey == s.id).toList();
        return section('Space', [
          _Text(label: 'Name', value: s.name, readOnly: ro, onChanged: (v) => n.edit((_, __) => s.name = v)),
          _Select(label: 'Type', value: s.type, options: st.catalog?.spaceTypes ?? const ['retail'], readOnly: ro, onChanged: (v) => n.edit((_, __) => s.type = v)),
          if (s.type == 'custom') _Text(label: 'Custom type', value: s.customType, readOnly: ro, onChanged: (v) => n.edit((_, __) => s.customType = v)),
          _Text(label: 'Unit type', value: s.unitType, readOnly: ro, onChanged: (v) => n.edit((_, __) => s.unitType = v)),
          _Text(label: 'Floor label', value: s.floorLabel, readOnly: ro, onChanged: (v) => n.edit((_, __) => s.floorLabel = v)),
          _Toggle(label: 'Sloped floor', value: s.sloped, readOnly: ro, onChanged: (v) => n.edit((_, __) => s.sloped = v)),
          _Toggle(label: 'Walkable', value: s.walkable, readOnly: ro, onChanged: (v) => n.edit((_, __) => s.walkable = v)),
          Text('Id ${s.id} · ${s.shape.outer.length} points · ${s.shape.holes.length} holes · ${s.shape.area.toStringAsFixed(1)} m²', style: ts(11, color: p.muted)),
          if (links.isNotEmpty) Text('Stores: ${links.map((l) => l.storeName).join(', ')}', style: ts(11, color: p.brand2)),
          gap(),
          if (!ro) AppButton(label: 'Add a hole', small: true, icon: Icons.crop_square, onPressed: () => n.setTool(EditorTool.hole)),
          gap(),
          if (!ro && s.shape.holes.isNotEmpty) AppButton(label: 'Remove last hole', small: true, onPressed: () => n.edit((_, __) => s.shape.holes.removeLast())),
          gap(),
          if (!ro) AppButton(label: 'Delete space', small: true, icon: Icons.delete_outline, onPressed: n.deleteSelection),
        ]);

      case SelKind.feature:
        final f = level.features.cast<Feature?>().firstWhere((x) => x!.id == sel.id, orElse: () => null);
        if (f == null) return const SizedBox.shrink();
        final def = st.catalog?.features[f.type];
        final rz = def?.resize;
        return section(def?.label ?? f.type, [
          _Text(label: 'Label', value: f.label, readOnly: ro, onChanged: (v) => n.edit((_, __) => f.label = v)),
          _Num(label: 'x', value: f.x, readOnly: ro, onChanged: (v) => n.edit((_, __) => f.x = v)),
          _Num(label: 'z', value: f.z, readOnly: ro, onChanged: (v) => n.edit((_, __) => f.z = v)),
          _Num(label: 'Rotation (°)', value: f.rot, step: 15, readOnly: ro, onChanged: (v) => n.edit((_, __) => f.rot = ((v % 360) + 360) % 360)),
          if (rz?['w'] != null) _Num(label: 'Width (m)', value: f.w ?? def!.size[0], min: rz!['w']![0], max: rz['w']![1], readOnly: ro, onChanged: (v) => n.edit((_, __) => f.w = v)),
          if (rz?['d'] != null) _Num(label: 'Depth (m)', value: f.d ?? def!.size[1], min: rz!['d']![0], max: rz['d']![1], readOnly: ro, onChanged: (v) => n.edit((_, __) => f.d = v)),
          if (rz?['h'] != null) _Num(label: 'Height (m)', value: f.h ?? def!.size[2], min: rz!['h']![0], max: rz['h']![1], readOnly: ro, onChanged: (v) => n.edit((_, __) => f.h = v)),
          if (def != null) Text('${def.target ? 'Navigation target' : 'Decoration'} · ${def.blocks ? 'blocks walking' : 'walk-through'}', style: ts(11, color: p.muted)),
          gap(),
          if (!ro) AppButton(label: 'Delete', small: true, icon: Icons.delete_outline, onPressed: n.deleteSelection),
        ]);

      case SelKind.connector:
        final c = doc.connectors.cast<Connector?>().firstWhere((x) => x!.id == sel.id, orElse: () => null);
        if (c == null) return const SizedBox.shrink();
        final kinds = st.catalog?.connectorKinds ?? const ['stairs'];
        final oneWayOk = st.catalog?.oneWayCapable.contains(c.kind) ?? false;
        return section('Connector', [
          _Text(label: 'Name', value: c.name, readOnly: ro, onChanged: (v) => n.edit((_, __) => c.name = v)),
          _Select(
            label: 'Kind',
            value: c.kind,
            options: kinds,
            readOnly: ro,
            onChanged: (v) => n.edit((_, __) {
              c.kind = v;
              if (!(st.catalog?.oneWayCapable.contains(v) ?? false)) c.oneWay = false;
            }),
          ),
          if (oneWayOk) _Toggle(label: 'One-way (first endpoint → second)', value: c.oneWay, readOnly: ro, onChanged: (v) => n.edit((_, __) => c.oneWay = v)),
          _Toggle(label: 'Walkable (used for routes)', value: c.walkable, readOnly: ro, onChanged: (v) => n.edit((_, __) => c.walkable = v)),
          gap(),
          Text('Endpoints (${c.endpoints.length})', style: ts(11, w: FontWeight.w700, color: p.ink)),
          for (final (i, e) in c.endpoints.indexed)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: p.boxBg, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('${i + 1}. ${doc.level(e.level)?.name ?? e.level} · ${doc.buildingOfLevel(e.level)?.name ?? ''}', style: ts(11, w: FontWeight.w700, color: p.ink))),
                      if (e.level != level.id) LinkButton('Go', onPressed: () => n.selectLevel(e.level)),
                      if (!ro && c.endpoints.length > 2)
                        IconButton(
                            padding: EdgeInsets.zero, constraints: const BoxConstraints(), iconSize: 16, icon: const Icon(Icons.close), onPressed: () => n.edit((_, __) => c.endpoints.removeAt(i))),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _Num(label: 'x', value: e.x, compact: true, readOnly: ro, onChanged: (v) => n.edit((_, __) => e.x = v))),
                      const SizedBox(width: 6),
                      Expanded(child: _Num(label: 'z', value: e.z, compact: true, readOnly: ro, onChanged: (v) => n.edit((_, __) => e.z = v))),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _Num(label: 'w', value: e.w, min: 0.5, max: 30, compact: true, readOnly: ro, onChanged: (v) => n.edit((_, __) => e.w = v))),
                      const SizedBox(width: 6),
                      Expanded(child: _Num(label: 'len', value: e.len, min: 0.5, max: 200, compact: true, readOnly: ro, onChanged: (v) => n.edit((_, __) => e.len = v))),
                      const SizedBox(width: 6),
                      Expanded(child: _Num(label: 'rot', value: e.rot, step: 15, compact: true, readOnly: ro, onChanged: (v) => n.edit((_, __) => e.rot = ((v % 360) + 360) % 360))),
                    ],
                  ),
                ],
              ),
            ),
          gap(),
          if (!ro) Text('To add an endpoint on another level: switch level, keep this connector selected, pick the Connector tool and click.', style: ts(11, color: p.muted)),
          gap(),
          if (!ro) AppButton(label: 'Delete connector', small: true, icon: Icons.delete_outline, onPressed: n.deleteSelection),
        ]);

      case SelKind.level:
      case SelKind.building:
      case SelKind.none:
        final b = st.building;
        return section('Level', [
          _Text(label: 'Level name', value: level.name, readOnly: ro, onChanged: (v) => n.edit((_, __) => level.name = v)),
          _Num(label: 'Elevation (m)', value: level.elevation, min: -50, max: 500, readOnly: ro, onChanged: (v) => n.edit((_, __) => level.elevation = v)),
          _Num(label: 'Height (m)', value: level.height, min: 2, max: 30, readOnly: ro, onChanged: (v) => n.edit((_, __) => level.height = v)),
          _Num(label: 'Offset x', value: level.offset[0], readOnly: ro, onChanged: (v) => n.edit((_, __) => level.offset = [v, level.offset[1]])),
          _Num(label: 'Offset z', value: level.offset[1], readOnly: ro, onChanged: (v) => n.edit((_, __) => level.offset = [level.offset[0], v])),
          _Num(label: 'Rotation (°)', value: level.rot, step: 15, readOnly: ro, onChanged: (v) => n.edit((_, __) => level.rot = ((v % 360) + 360) % 360)),
          Text(
            level.outline == null
                ? 'No outline yet. Use the Outline tool.'
                : 'Outline: ${level.outline!.outer.length} points, ${level.outline!.holes.length} holes, ${level.outline!.area.toStringAsFixed(0)} m²',
            style: ts(11, color: p.muted),
          ),
          gap(),
          if (!ro) AppButton(label: 'Select outline (edit points)', small: true, onPressed: () => n.select(Selection(SelKind.level, level.id))),
          gap(),
          if (!ro) AppButton(label: 'Draw outline', small: true, icon: Icons.polyline, onPressed: () => n.setTool(EditorTool.outline)),
          gap(),
          if (!ro)
            AppButton(
              label: 'Add hole to outline (atrium / void)',
              small: true,
              onPressed: () {
                n.select(Selection.none);
                n.setTool(EditorTool.hole);
              },
            ),
          const SizedBox(height: 16),
          if (b != null) ...[
            Text('BUILDING', style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1)),
            const SizedBox(height: 8),
            _Text(label: 'Building name', value: b.name, readOnly: ro, onChanged: (v) => n.edit((_, __) => b.name = v)),
            _Num(label: 'Origin x (branch grid)', value: b.origin[0], readOnly: ro, onChanged: (v) => n.edit((_, __) => b.origin = [v, b.origin[1]])),
            _Num(label: 'Origin z (branch grid)', value: b.origin[1], readOnly: ro, onChanged: (v) => n.edit((_, __) => b.origin = [b.origin[0], v])),
            _Num(label: 'Rotation (°)', value: b.rot, step: 15, readOnly: ro, onChanged: (v) => n.edit((_, __) => b.rot = ((v % 360) + 360) % 360)),
          ],
        ]);
    }
  }
}

// ---- small controls (commit on submit / focus loss, so typing stays smooth) ----

class _Text extends StatefulWidget {
  const _Text({required this.label, required this.value, required this.onChanged, this.readOnly = false});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool readOnly;

  @override
  State<_Text> createState() => _TextState();
}

class _TextState extends State<_Text> {
  late final _c = TextEditingController(text: widget.value);
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus && _c.text != widget.value) widget.onChanged(_c.text);
    });
  }

  @override
  void didUpdateWidget(covariant _Text old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_f.hasFocus) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _c,
        focusNode: _f,
        readOnly: widget.readOnly,
        style: ts(12, color: p.ink),
        onSubmitted: widget.onChanged,
        decoration: InputDecoration(
          isDense: true,
          labelText: widget.label,
          labelStyle: ts(11, color: p.muted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: p.fieldLine)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: p.fieldLine)),
        ),
      ),
    );
  }
}

class _Num extends StatefulWidget {
  const _Num({required this.label, required this.value, required this.onChanged, this.min, this.max, this.step = 0.1, this.readOnly = false, this.compact = false});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double? min;
  final double? max;
  final double step;
  final bool readOnly;
  final bool compact;

  @override
  State<_Num> createState() => _NumState();
}

class _NumState extends State<_Num> {
  late final _c = TextEditingController(text: _fmt(widget.value));
  final _f = FocusNode();

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

  void _commit() {
    final v = double.tryParse(_c.text.trim());
    if (v == null) {
      _c.text = _fmt(widget.value);
      return;
    }
    var x = v;
    if (widget.min != null && x < widget.min!) x = widget.min!;
    if (widget.max != null && x > widget.max!) x = widget.max!;
    if (x != widget.value) widget.onChanged(x);
    _c.text = _fmt(x);
  }

  void _nudge(double delta) {
    _c.text = _fmt(widget.value + delta);
    _commit();
  }

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _Num old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_f.hasFocus) _c.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: EdgeInsets.only(bottom: widget.compact ? 4 : 8),
      child: TextField(
        controller: _c,
        focusNode: _f,
        readOnly: widget.readOnly,
        style: ts(12, color: p.ink),
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          isDense: true,
          labelText: widget.label,
          labelStyle: ts(11, color: p.muted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: p.fieldLine)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: p.fieldLine)),
          suffixIcon: widget.readOnly
              ? null
              : SizedBox(
                  width: 44,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(onTap: () => _nudge(-widget.step), child: Icon(Icons.remove, size: 14, color: p.muted)),
                      InkWell(onTap: () => _nudge(widget.step), child: Icon(Icons.add, size: 14, color: p.muted)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Select extends StatelessWidget {
  const _Select({required this.label, required this.value, required this.options, required this.onChanged, this.readOnly = false});

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          labelStyle: ts(11, color: p.muted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: p.fieldLine)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: p.fieldLine)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: options.contains(value) ? value : options.first,
            isDense: true,
            isExpanded: true,
            style: ts(12, color: p.ink),
            dropdownColor: p.panel,
            items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o.replaceAll('_', ' ')))],
            onChanged: readOnly ? null : (v) => v == null ? null : onChanged(v),
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.value, required this.onChanged, this.readOnly = false});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: ts(12, color: p.ink))),
          Switch(value: value, onChanged: readOnly ? null : onChanged, activeThumbColor: p.brand),
        ],
      ),
    );
  }
}
