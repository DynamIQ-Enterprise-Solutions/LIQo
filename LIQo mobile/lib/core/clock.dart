import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The time now. Opening hours and the trip history read it from here, so
/// tests can fix it.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
