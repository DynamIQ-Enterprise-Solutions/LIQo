import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How far the phone's clock is off from the shopper server's, as last seen online (the server
/// time minus the phone's). Opening hours and post end dates use the corrected time.
class ClockSkew extends Notifier<Duration> {
  @override
  Duration build() => Duration.zero;

  /// Ignored when the difference is under a minute (network delay) or absurd (a broken reply).
  void seen(DateTime server, DateTime phone) {
    final d = server.difference(phone);
    state = d.abs() < const Duration(minutes: 1) || d.abs() > const Duration(days: 400) ? Duration.zero : d;
  }
}

final clockSkewProvider = NotifierProvider<ClockSkew, Duration>(ClockSkew.new);

/// The time now (corrected by the server's clock when known). Opening hours and the trip history
/// read it from here, so tests can fix it.
final clockProvider = Provider<DateTime Function()>((ref) {
  final skew = ref.watch(clockSkewProvider);
  return skew == Duration.zero ? DateTime.now : () => DateTime.now().add(skew);
});
