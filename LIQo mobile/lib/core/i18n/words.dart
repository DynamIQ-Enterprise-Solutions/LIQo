import 'tagalog.dart';

/// The app's wording in the shopper's language. Text is always written in plain
/// English first; [tr] turns it into everyday Tagalog when that is chosen
/// (the demo's `T(plain, technical)`, without the technical wording).
class Words {
  const Words(this.lang);

  /// en | tl
  final String lang;

  bool get tagalogOn => lang == 'tl';

  String tr(String en) => tagalogOn ? tagalog(en) : en;
}
