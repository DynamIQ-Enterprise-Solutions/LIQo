import 'package:web/web.dart' as web;

/// Points every `rel=icon` link at the tile for this mode, and tells the
/// browser the matching theme colour for its own chrome.
void setFavicon({required bool dark}) {
  final href = dark ? 'favicon-dark.png' : 'favicon-light.png';
  final links = web.document.querySelectorAll('link[rel="icon"]');
  for (var i = 0; i < links.length; i++) {
    final el = links.item(i) as web.Element?;
    if (el == null) continue;
    el.setAttribute('href', href);
    el.removeAttribute('media');
  }
  final meta = web.document.querySelector('meta[name="theme-color"]');
  meta?.setAttribute('content', dark ? '#15151A' : '#FFFFFF');
}
