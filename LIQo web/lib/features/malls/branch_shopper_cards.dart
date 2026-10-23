import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/field_builder.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import 'malls_service.dart';

/// The branch's location for the shopper app (Round 21, owner decision
/// 2026-10-23): the admin pastes a Google Maps link, the server reads the pin
/// and the place's name, and the name is shown back to confirm. The pin's
/// numbers stay off the screens.
class BranchLocationCard extends StatefulWidget {
  const BranchLocationCard({super.key, required this.branch, required this.canEdit, required this.service, required this.onSaved, required this.onMessage});

  final Branch branch;
  final bool canEdit;
  final MallsService service;
  final ValueChanged<Branch> onSaved;
  final void Function(String text, {bool error}) onMessage;

  @override
  State<BranchLocationCard> createState() => _BranchLocationCardState();
}

class _BranchLocationCardState extends State<BranchLocationCard> {
  bool _editing = false;
  bool _busy = false;
  String _link = '';
  String? _checkedLink;
  String? _found;
  String? _error;

  Future<void> _check() async {
    final link = _link.trim();
    if (link.isEmpty) return setState(() => _error = 'Paste a Google Maps link first.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = await widget.service.checkLocation(widget.branch.id, link);
      setState(() {
        _checkedLink = link;
        _found = name ?? 'A pin with no place name';
      });
    } catch (e) {
      setState(() {
        _checkedLink = null;
        _error = formatApiError(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String? link) async {
    setState(() => _busy = true);
    try {
      final b = await widget.service.setLocation(widget.branch.id, link);
      widget.onSaved(b);
      widget.onMessage(link == null ? 'Location removed.' : 'Location saved.');
      setState(() {
        _editing = false;
        _checkedLink = null;
        _found = null;
      });
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final b = widget.branch;
    final has = b.mapsLink != null;
    return DetailCard(
      title: 'Location',
      subtitle: 'Where shoppers find this branch on Google Maps',
      trailing: widget.canEdit && !_editing ? AppButton(label: has ? 'Change' : 'Add location', small: true, icon: Icons.place_outlined, onPressed: () => setState(() => _editing = true)) : null,
      child: _editing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldBuilder(
                  key: const ValueKey('maps-link'),
                  spec: const FieldSpec(
                    name: 'mapsLink',
                    label: 'Google Maps link',
                    hint: 'https://maps.app.goo.gl/…',
                    help: 'In Google Maps, open the branch itself, tap Share, copy the link and paste it here.',
                  ),
                  value: _link,
                  onChanged: (v) => setState(() {
                    _link = (v as String?) ?? '';
                    if (_link.trim() != _checkedLink) _found = null;
                  }),
                ),
                if (_found != null && _checkedLink == _link.trim())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('Pin: $_found. Is this the branch?', key: const ValueKey('maps-found'), style: ts(13, w: FontWeight.w600, color: p.ink)),
                  ),
                if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: ts(12, color: p.warn))),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_found != null && _checkedLink == _link.trim())
                      AppButton(label: 'Yes, save', primary: true, small: true, onPressed: _busy ? () {} : () => _save(_checkedLink))
                    else
                      AppButton(label: _busy ? 'Checking…' : 'Check the link', primary: true, small: true, onPressed: _busy ? () {} : _check),
                    AppButton(label: 'Cancel', small: true, onPressed: () => setState(() => _editing = false)),
                    if (has) AppButton(label: 'Remove location', small: true, onPressed: _busy ? () {} : () => _save(null)),
                  ],
                ),
              ],
            )
          : has
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The link holds the pin's numbers, which stay off the screens (owner decision 2026-10-21).
                    DetailRow('Place', b.placeName ?? 'A pin with no place name'),
                    Text('Set from a Google Maps link. Change it to move the pin.', style: ts(11.5, color: p.muted)),
                  ],
                )
              : Text('No location yet. Shoppers use it to find the branch and to get there.', style: ts(12, color: p.muted)),
    );
  }
}

/// Lifts, escalators and stairs on the published map, and which are out of
/// service (Round 21). Mall admins mark and clear; phones route around them.
class OutOfServiceCard extends StatelessWidget {
  const OutOfServiceCard({super.key, required this.published, required this.items, required this.canEdit, required this.onToggle});

  final bool published;
  final List<MapConnector> items;
  final bool canEdit;
  final Future<void> Function(MapConnector c, bool out) onToggle;

  static final _fmt = DateFormat('MMM d, h:mm a');

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final out = items.where((c) => c.outOfService).length;
    return DetailCard(
      title: 'Lifts, escalators and stairs',
      subtitle: !published ? 'Comes with the published map' : (out == 0 ? 'All in service' : '$out out of service'),
      child: !published || items.isEmpty
          ? Text(
              !published ? 'Once the map is published, mark a lift, escalator or stairs out of service here; phones then route around it.' : 'The published map has no lifts, escalators or stairs.',
              style: ts(12, color: p.muted),
            )
          : Column(
              children: [
                for (final c in items)
                  RecordRow(
                    key: ValueKey('connector-${c.id}'),
                    title: c.name ?? c.kindLabel,
                    subtitle: [
                      if (c.name != null) c.kindLabel,
                      if (c.levels.isNotEmpty) c.levels.join(', '),
                      if (c.outOfService && c.since != null) 'since ${_fmt.format(c.since!)}${c.markedByName == null ? '' : ' · ${c.markedByName}'}',
                    ].join(' · '),
                    chips: [c.outOfService ? const Pill('Out of service', kind: PillKind.pending) : const Pill('In service')],
                    actions: [
                      if (canEdit)
                        AppButton(
                          label: c.outOfService ? 'Back in service' : 'Out of service',
                          small: true,
                          icon: c.outOfService ? Icons.check_circle_outline : Icons.block,
                          onPressed: () => onToggle(c, !c.outOfService),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}
