import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';

enum MessageKind { info, success, error }

class AppMessage {
  const AppMessage(this.text, this.kind);

  final String text;
  final MessageKind kind;
}

/// The one place the app shows short messages. Mounted above the Navigator in
/// MaterialApp.builder so it floats over dialogs as well.
class MessagesNotifier extends Notifier<AppMessage?> {
  Timer? _timer;

  @override
  AppMessage? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(String text, {MessageKind kind = MessageKind.info}) {
    _timer?.cancel();
    state = AppMessage(text, kind);
    _timer = Timer(const Duration(milliseconds: 3200), () => state = null);
  }

  void showError(String text) => show(text, kind: MessageKind.error);
  void showSuccess(String text) => show(text, kind: MessageKind.success);
  void dismiss() {
    _timer?.cancel();
    state = null;
  }
}

final messagesProvider = NotifierProvider<MessagesNotifier, AppMessage?>(MessagesNotifier.new);

class MessageOverlay extends ConsumerWidget {
  const MessageOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(messagesProvider);
    final p = context.pal;
    final wide = MediaQuery.sizeOf(context).width > 520;

    final Color bg;
    final IconData icon;
    switch (message?.kind) {
      case MessageKind.error:
        bg = p.toastError;
        icon = Icons.error_outline;
        break;
      case MessageKind.success:
        bg = p.toastSuccess;
        icon = Icons.check_circle_outline;
        break;
      default:
        bg = p.toastInfo;
        icon = Icons.info_outline;
    }

    return Stack(
      children: [
        child,
        Positioned(
          right: wide ? 22 : 16,
          left: wide ? null : 16,
          bottom: 22,
          child: IgnorePointer(
            ignoring: message == null,
            child: AnimatedOpacity(
              opacity: message == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: p.shadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message?.text ?? '',
                          style: ts(12, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => ref.read(messagesProvider.notifier).dismiss(),
                        child: const Icon(Icons.close, size: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
