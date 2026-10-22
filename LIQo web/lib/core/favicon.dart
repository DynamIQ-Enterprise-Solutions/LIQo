// Swaps the browser-tab icon with the mode (dark tile in dark mode, light tile
// in light mode). The web build has the real one; the VM gets a stub.
export 'favicon_stub.dart' if (dart.library.js_interop) 'favicon_web.dart';
