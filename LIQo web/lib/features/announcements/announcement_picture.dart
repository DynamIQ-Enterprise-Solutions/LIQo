import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import '../../shared/widgets/skeleton.dart';
import 'announcements_service.dart';

/// A chosen picture: its bytes and name, or null when nothing was picked.
typedef PictureFilePicker = Future<(Uint8List, String)?> Function();

/// How an announcement's picture is chosen. Tests replace it with a fake.
final announcementPicturePickerProvider = Provider<PictureFilePicker>((ref) => () async {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg']);
      final file = picked.firstOrNull;
      if (file == null) return null;
      return (await file.readAsBytes(), file.name);
    });

/// The announcement's one picture (Round 21, owner decision 2026-10-23: an
/// upload replaces the old image link). PNG or JPEG up to 2 MB. Those who may
/// change the announcement upload, replace or remove it; a store owner's change
/// goes back for review.
class AnnouncementPictureCard extends ConsumerStatefulWidget {
  const AnnouncementPictureCard({super.key, required this.announcement, required this.canChange, required this.owner, required this.service, required this.onChanged, required this.onMessage});

  final Announcement announcement;
  final bool canChange;

  /// The viewer is a store owner (a change sends it back for review).
  final bool owner;
  final AnnouncementsService service;
  final ValueChanged<Announcement> onChanged;
  final void Function(String text, {bool error}) onMessage;

  @override
  ConsumerState<AnnouncementPictureCard> createState() => _AnnouncementPictureCardState();
}

class _AnnouncementPictureCardState extends ConsumerState<AnnouncementPictureCard> {
  Uint8List? _bytes;
  String? _loadedKey;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant AnnouncementPictureCard old) {
    super.didUpdateWidget(old);
    if (widget.announcement.imageKey != _loadedKey) _fetch();
  }

  Future<void> _fetch() async {
    final key = widget.announcement.imageKey;
    _loadedKey = key;
    if (key == null) {
      if (_bytes != null) setState(() => _bytes = null);
      return;
    }
    try {
      final bytes = await widget.service.pictureBytes(widget.announcement.id);
      if (mounted && widget.announcement.imageKey == key) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _bytes = null);
    }
  }

  Future<void> _upload() async {
    final picked = await ref.read(announcementPicturePickerProvider)();
    if (picked == null) return;
    final (bytes, name) = picked;
    if (bytes.length > 2 * 1024 * 1024) return widget.onMessage('The picture is larger than 2 MB. Use a smaller picture.', error: true);
    setState(() => _busy = true);
    try {
      final updated = await widget.service.uploadPicture(widget.announcement.id, bytes, name);
      widget.onChanged(updated);
      widget.onMessage(widget.owner && updated.status == 'pending' && widget.announcement.status != 'pending' ? 'Picture saved. It goes back for review.' : 'Picture saved.');
    } catch (e) {
      widget.onMessage(formatApiError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await confirmDialog(context, title: 'Remove the picture?', message: 'Shoppers see the announcement without it.', confirmLabel: 'Remove');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      widget.onChanged(await widget.service.removePicture(widget.announcement.id));
      widget.onMessage('Picture removed.');
    } catch (e) {
      widget.onMessage(formatApiError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final a = widget.announcement;
    final has = a.imageKey != null;
    return DetailCard(
      title: 'Picture',
      subtitle: has ? 'Shown with the announcement in the shopper app' : 'Optional · PNG or JPEG up to 2 MB',
      trailing: widget.canChange
          ? Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AppButton(key: const ValueKey('picture-upload'), label: _busy ? 'Uploading…' : (has ? 'Replace' : 'Upload picture'), small: true, icon: Icons.image_outlined, onPressed: _busy ? () {} : _upload),
                if (has) DangerButton(label: 'Remove', onPressed: _busy ? () {} : _remove),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (has)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: _bytes == null
                    ? const AspectRatio(aspectRatio: 16 / 9, child: SkeletonBox())
                    : Image.memory(_bytes!, fit: BoxFit.contain, semanticLabel: 'Announcement picture'),
              ),
            )
          else
            Text('No picture.', style: ts(12, color: p.muted)),
          if (!has && a.imageUrl != null) ...[
            const SizedBox(height: 8),
            DetailRow('Old image link', a.imageUrl, child: SelectableText(a.imageUrl!, style: ts(11.5, color: p.muted))),
            Text('Shown until the announcement is edited. Upload a picture to replace it.', style: ts(11, color: p.muted)),
          ],
        ],
      ),
    );
  }
}
